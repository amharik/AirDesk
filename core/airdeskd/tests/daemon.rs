use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use airdeskd::{
    handle_connection, Clock, Daemon, DaemonConfig, PtyConfig, PtyHandle, PtySpawner, ReplayBuffer,
    SpawnedPty, TerminalFrame, TerminalFrameType, TerminalLease, UnixPtySpawner,
};
use std::io::Write;
use std::os::unix::net::UnixStream;

#[derive(Default)]
struct FakeState {
    written: Mutex<Vec<u8>>,
    resized: Mutex<Vec<(u16, u16)>>,
    output: Mutex<Option<SyncSender<Vec<u8>>>>,
    exit: Mutex<Option<SyncSender<i32>>>,
    spawns: AtomicUsize,
}

impl FakeState {
    fn emit(&self, data: &[u8]) {
        let guard = self.output.lock().unwrap();
        guard.as_ref().unwrap().send(data.to_vec()).unwrap();
    }
}

#[derive(Clone, Default)]
struct FakeSpawner(Arc<FakeState>);

impl PtySpawner for FakeSpawner {
    fn spawn(&self, _config: &PtyConfig) -> std::io::Result<SpawnedPty> {
        self.0.spawns.fetch_add(1, Ordering::SeqCst);
        let (output_tx, output_rx) = sync_channel(64);
        let (exit_tx, exit_rx) = sync_channel(1);
        *self.0.output.lock().unwrap() = Some(output_tx);
        *self.0.exit.lock().unwrap() = Some(exit_tx);
        Ok(SpawnedPty {
            handle: Box::new(FakeHandle(self.0.clone())),
            output: output_rx,
            exit: exit_rx,
        })
    }
}

struct FakeHandle(Arc<FakeState>);

impl PtyHandle for FakeHandle {
    fn write(&mut self, data: &[u8]) -> std::io::Result<()> {
        self.0.written.lock().unwrap().extend_from_slice(data);
        Ok(())
    }

    fn resize(&mut self, columns: u16, rows: u16) -> std::io::Result<()> {
        self.0.resized.lock().unwrap().push((columns, rows));
        Ok(())
    }

    fn close(&mut self) {}
}

fn lease() -> TerminalLease {
    TerminalLease::new(
        "lease-1",
        "workspace",
        "application",
        "requester",
        "s1",
        ["attach", "write", "resize", "detach"],
    )
    .unwrap()
}

fn daemon(spawner: Arc<dyn PtySpawner>) -> Arc<Daemon> {
    let now: Clock = Arc::new(|| 1_000);
    let daemon = Daemon::new(
        DaemonConfig::new(PtyConfig::shell("/bin/sh", Vec::new(), 80, 24)),
        spawner,
        Default::default(),
        now,
    );
    daemon.grant_lease(lease()).unwrap();
    Arc::new(daemon)
}

fn attach(daemon: &Daemon, client: &str, after: u64) -> Receiver<TerminalFrame> {
    let (sender, receiver) = sync_channel(64);
    daemon
        .handle(
            TerminalFrame::attach("s1", client, "lease-1", after),
            sender,
        )
        .unwrap();
    receiver
}

fn recv(receiver: &Receiver<TerminalFrame>) -> TerminalFrame {
    receiver.recv_timeout(Duration::from_secs(2)).unwrap()
}

#[test]
fn frame_round_trip_uses_length_prefix() {
    let frame = TerminalFrame::data("s1", "client", 42, b"raw\0pty\xff".to_vec());
    let bytes = frame.encode().unwrap();
    assert_eq!(TerminalFrame::decode(&bytes).unwrap(), frame);

    let mut buffer = Vec::new();
    frame.write_to(&mut buffer).unwrap();
    let mut reader = std::io::Cursor::new(buffer);
    assert_eq!(TerminalFrame::read_from(&mut reader).unwrap(), frame);
}

#[test]
fn replay_buffer_is_bounded_and_reports_truncation() {
    let mut replay = ReplayBuffer::new(8, 8);
    for byte in b"abcdefghijkl" {
        replay.push(&[*byte]);
    }
    assert!(replay.retained_bytes() <= 8);
    assert!(replay.oldest_sequence() > 1);

    let result = replay.after(0);
    assert!(result.truncated);
    assert_eq!(result.chunks.len(), replay.retained_chunks());
    assert_eq!(
        result
            .chunks
            .iter()
            .map(|chunk| chunk.data[0])
            .collect::<Vec<_>>(),
        b"efghijkl".to_vec()
    );
}

#[test]
fn multiple_clients_attach_and_receive_the_same_output() {
    let fake = FakeSpawner::default();
    let daemon = daemon(Arc::new(fake.clone()));

    let first = attach(&daemon, "first", 0);
    assert_eq!(recv(&first).frame_type, TerminalFrameType::Attached);
    fake.0.emit(b"hello");
    let data = recv(&first);
    assert_eq!(data.frame_type, TerminalFrameType::Data);
    assert_eq!(data.sequence, 1);
    assert_eq!(data.data, b"hello");

    let second = attach(&daemon, "second", 0);
    assert_eq!(recv(&second).frame_type, TerminalFrameType::Attached);
    let replay = recv(&second);
    assert_eq!(replay.data, b"hello");

    fake.0.emit(b" world");
    let first_data = recv(&first);
    let second_data = recv(&second);
    assert_eq!(first_data.data, b" world");
    assert_eq!(second_data.data, b" world");
    assert_eq!(first_data.sequence, second_data.sequence);
}

#[test]
fn reconnect_replays_only_chunks_after_the_acknowledged_sequence() {
    let fake = FakeSpawner::default();
    let daemon = daemon(Arc::new(fake.clone()));

    let first = attach(&daemon, "client", 0);
    recv(&first);
    fake.0.emit(b"one");
    let first_data = recv(&first);
    assert_eq!(first_data.sequence, 1);
    fake.0.emit(b"two");
    let second_data = recv(&first);
    assert_eq!(second_data.sequence, 2);
    daemon
        .handle(
            TerminalFrame::request(TerminalFrameType::Detach, "s1", "client", "lease-1"),
            sync_channel(1).0,
        )
        .unwrap();

    let reconnected = attach(&daemon, "client", 1);
    let attached = recv(&reconnected);
    assert_eq!(attached.frame_type, TerminalFrameType::Attached);
    assert_eq!(attached.oldest_sequence, 1);
    assert_eq!(attached.sequence, 3);
    assert!(!attached.truncated);
    let replay = recv(&reconnected);
    assert_eq!(replay.sequence, 2);
    assert_eq!(replay.data, b"two");
}

#[test]
fn leases_are_required_and_can_be_revoked_or_expired() {
    let fake = FakeSpawner::default();
    let daemon = daemon(Arc::new(fake.clone()));

    let (sender, _receiver) = sync_channel(8);
    let error = daemon
        .handle(TerminalFrame::attach("s1", "client", "missing", 0), sender)
        .unwrap_err();
    assert!(error.to_string().contains("LeaseDenied"));

    let frames = attach(&daemon, "client", 0);
    recv(&frames);
    daemon
        .handle(
            TerminalFrame::request(TerminalFrameType::Data, "s1", "client", "lease-1"),
            sync_channel(8).0,
        )
        .unwrap();

    daemon.revoke_lease("lease-1", "test").unwrap();
    let (sender, _receiver) = sync_channel(8);
    let error = daemon
        .handle(
            TerminalFrame::request(TerminalFrameType::Data, "s1", "other", "lease-1"),
            sender,
        )
        .unwrap_err();
    assert!(error.to_string().contains("LeaseRevoked"));

    let mut expiring = TerminalLease::new(
        "expired",
        "workspace",
        "application",
        "requester",
        "s1",
        ["attach"],
    )
    .unwrap();
    expiring.expires_at_ms = 999;
    daemon.grant_lease(expiring).unwrap();
    let (sender, _receiver) = sync_channel(8);
    let error = daemon
        .handle(TerminalFrame::attach("s1", "late", "expired", 0), sender)
        .unwrap_err();
    assert!(error.to_string().contains("LeaseExpired"));
}

#[test]
fn writes_and_resizes_require_an_attached_client() {
    let fake = FakeSpawner::default();
    let daemon = daemon(Arc::new(fake.clone()));

    let (sender, _receiver) = sync_channel(8);
    let error = daemon
        .handle(
            TerminalFrame::request(TerminalFrameType::Data, "s1", "client", "lease-1"),
            sender,
        )
        .unwrap_err();
    assert!(error.to_string().contains("TerminalNotAttached"));

    let frames = attach(&daemon, "client", 0);
    recv(&frames);

    let mut write = TerminalFrame::request(TerminalFrameType::Data, "s1", "client", "lease-1");
    write.data = b"ls\r".to_vec();
    daemon.handle(write, sync_channel(8).0).unwrap();
    assert_eq!(&*fake.0.written.lock().unwrap(), b"ls\r");

    let mut resize = TerminalFrame::request(TerminalFrameType::Resize, "s1", "client", "lease-1");
    resize.columns = 120;
    resize.rows = 40;
    daemon.handle(resize, sync_channel(8).0).unwrap();
    assert_eq!(&*fake.0.resized.lock().unwrap(), &[(120, 40)]);
}

#[test]
fn socket_connection_carries_adfp_frames() {
    let fake = FakeSpawner::default();
    let daemon = daemon(Arc::new(fake.clone()));
    let (server, mut client) = UnixStream::pair().unwrap();
    client
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    let handle = thread::spawn(move || handle_connection(server, daemon));

    TerminalFrame::attach("s1", "socket-client", "lease-1", 0)
        .write_to(&mut client)
        .unwrap();
    let attached = TerminalFrame::read_from(&mut client).unwrap();
    assert_eq!(attached.frame_type, TerminalFrameType::Attached);
    assert_eq!(attached.client_id.as_deref(), Some("socket-client"));

    fake.0.emit(b"socket");
    let data = TerminalFrame::read_from(&mut client).unwrap();
    assert_eq!(data.data, b"socket");

    client.flush().unwrap();
    drop(client);
    handle.join().unwrap().unwrap();
}

#[test]
fn unix_pty_byte_tees_raw_output() {
    let now: Clock = Arc::new(|| 1_000);
    let config = DaemonConfig::new(PtyConfig::shell(
        "/bin/sh",
        vec![
            "-c".to_string(),
            "printf 'airdesk-pty'; sleep 0.05".to_string(),
        ],
        80,
        24,
    ));
    let daemon = Daemon::new(config, Arc::new(UnixPtySpawner), Default::default(), now);
    daemon.grant_lease(lease()).unwrap();

    let frames = attach(&daemon, "pty-client", 0);
    recv(&frames);
    let mut output = Vec::new();
    loop {
        match frames.recv_timeout(Duration::from_secs(2)) {
            Ok(frame) if frame.frame_type == TerminalFrameType::Data => {
                output.extend_from_slice(&frame.data);
            }
            Ok(frame) if frame.frame_type == TerminalFrameType::Exit => break,
            Ok(_) => {}
            Err(error) => panic!("PTY test timed out: {error}"),
        }
    }
    assert!(output
        .windows(b"airdesk-pty".len())
        .any(|window| window == b"airdesk-pty"));
}

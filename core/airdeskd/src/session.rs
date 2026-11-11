use std::collections::HashMap;
use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::mpsc::{SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::frame::{TerminalFrame, TerminalFrameType};
use crate::lease::{LeaseError, LeaseRegistry, TerminalLease};
use crate::pty::{PtyConfig, PtyHandle, PtySpawner};
use crate::replay::{ReplayBuffer, DEFAULT_MAX_REPLAY_BYTES, DEFAULT_MAX_REPLAY_CHUNKS};

pub const DEFAULT_MAX_CLIENTS: usize = 8;

pub type Clock = Arc<dyn Fn() -> u64 + Send + Sync>;

#[derive(Debug, Clone)]
pub struct DaemonConfig {
    pub pty: PtyConfig,
    pub max_replay_bytes: usize,
    pub max_replay_chunks: usize,
    pub max_clients: usize,
}

impl DaemonConfig {
    pub fn new(pty: PtyConfig) -> Self {
        Self {
            pty,
            max_replay_bytes: DEFAULT_MAX_REPLAY_BYTES,
            max_replay_chunks: DEFAULT_MAX_REPLAY_CHUNKS,
            max_clients: DEFAULT_MAX_CLIENTS,
        }
    }
}

pub struct Daemon {
    config: DaemonConfig,
    spawner: Arc<dyn PtySpawner>,
    leases: Mutex<LeaseRegistry>,
    sessions: Mutex<HashMap<String, Arc<Session>>>,
    now: Clock,
}

impl Daemon {
    pub fn new(
        config: DaemonConfig,
        spawner: Arc<dyn PtySpawner>,
        leases: LeaseRegistry,
        now: Clock,
    ) -> Self {
        Self {
            config,
            spawner,
            leases: Mutex::new(leases),
            sessions: Mutex::new(HashMap::new()),
            now,
        }
    }

    pub fn grant_lease(&self, lease: TerminalLease) -> Result<(), LeaseError> {
        self.leases.lock().unwrap().grant(lease)
    }

    pub fn revoke_lease(&self, lease_id: &str, reason: &str) -> Result<(), LeaseError> {
        self.leases.lock().unwrap().revoke(lease_id, reason)
    }

    pub fn handle(
        &self,
        frame: TerminalFrame,
        sink: SyncSender<TerminalFrame>,
    ) -> Result<(), TerminalError> {
        let client_id = frame
            .client_id
            .as_deref()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| TerminalError::Invalid("client id".to_string()))?
            .to_string();
        match frame.frame_type {
            TerminalFrameType::Attach => {
                self.authorize(&frame, "attach")?;
                let session = self.session(&frame.session_id)?;
                session.attach(&client_id, sink, frame.replay_from_sequence)
            }
            TerminalFrameType::Resize => {
                self.authorize(&frame, "resize")?;
                self.session(&frame.session_id)?
                    .resize(&client_id, frame.columns, frame.rows)
            }
            TerminalFrameType::Detach => {
                self.authorize(&frame, "detach")?;
                self.sessions
                    .lock()
                    .unwrap()
                    .get(&frame.session_id)
                    .ok_or(TerminalError::SessionNotFound)?
                    .detach(&client_id);
                Ok(())
            }
            TerminalFrameType::Data => {
                self.authorize(&frame, "write")?;
                self.session(&frame.session_id)?
                    .write(&client_id, &frame.data)
            }
            TerminalFrameType::Attached | TerminalFrameType::Exit | TerminalFrameType::Error => {
                Err(TerminalError::Invalid("client message type".to_string()))
            }
        }
    }

    pub fn detach_client(&self, client_id: &str) {
        let sessions = self
            .sessions
            .lock()
            .unwrap()
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for session in sessions {
            session.detach(client_id);
        }
    }

    fn authorize(&self, frame: &TerminalFrame, operation: &str) -> Result<(), TerminalError> {
        let now = (self.now)();
        self.leases
            .lock()
            .unwrap()
            .authorize(frame.lease_id.as_deref(), operation, &frame.session_id, now)
            .map(|_| ())
            .map_err(TerminalError::Lease)
    }

    fn session(&self, session_id: &str) -> Result<Arc<Session>, TerminalError> {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(session) = sessions.get(session_id) {
            return Ok(session.clone());
        }
        let spawned = self
            .spawner
            .spawn(&self.config.pty)
            .map_err(|error| TerminalError::Spawn(error.to_string()))?;
        let session = Session::new(
            session_id.to_string(),
            spawned,
            self.config.max_replay_bytes,
            self.config.max_replay_chunks,
            self.config.max_clients,
        );
        sessions.insert(session_id.to_string(), session.clone());
        Ok(session)
    }
}

struct Session {
    id: String,
    pty: Mutex<Box<dyn PtyHandle>>,
    replay: Mutex<ReplayBuffer>,
    clients: Mutex<HashMap<String, SyncSender<TerminalFrame>>>,
    publish: Mutex<()>,
    max_clients: usize,
    closed: AtomicBool,
    exit_code: AtomicI32,
}

impl Session {
    fn new(
        id: String,
        spawned: crate::pty::SpawnedPty,
        max_replay_bytes: usize,
        max_replay_chunks: usize,
        max_clients: usize,
    ) -> Arc<Self> {
        let session = Arc::new(Self {
            id,
            pty: Mutex::new(spawned.handle),
            replay: Mutex::new(ReplayBuffer::new(max_replay_bytes, max_replay_chunks)),
            clients: Mutex::new(HashMap::new()),
            publish: Mutex::new(()),
            max_clients,
            closed: AtomicBool::new(false),
            exit_code: AtomicI32::new(0),
        });

        let output_session = session.clone();
        let output = spawned.output;
        std::thread::spawn(move || {
            while let Ok(data) = output.recv() {
                output_session.publish_data(&data);
            }
            let exit_code = spawned
                .exit
                .recv_timeout(Duration::from_secs(2))
                .unwrap_or(-1);
            output_session.publish_exit(exit_code);
        });
        session
    }

    fn attach(
        &self,
        client_id: &str,
        sink: SyncSender<TerminalFrame>,
        after_sequence: u64,
    ) -> Result<(), TerminalError> {
        if client_id.is_empty() || client_id.len() > 128 || client_id.contains('\0') {
            return Err(TerminalError::Invalid("client id".to_string()));
        }
        let _guard = self.publish.lock().unwrap();
        let replay = self.replay.lock().unwrap().after(after_sequence);
        {
            let mut clients = self.clients.lock().unwrap();
            if !clients.contains_key(client_id) && clients.len() >= self.max_clients {
                return Err(TerminalError::TooManyClients);
            }
            clients.insert(client_id.to_string(), sink.clone());
        }

        let result = (|| {
            send(
                &sink,
                TerminalFrame::attached(
                    &self.id,
                    client_id,
                    replay.oldest_sequence,
                    replay.next_sequence,
                    replay.truncated,
                ),
            )?;
            for chunk in replay.chunks {
                send(
                    &sink,
                    TerminalFrame::data(&self.id, client_id, chunk.sequence, chunk.data),
                )?;
            }
            if self.closed.load(Ordering::SeqCst) {
                send(&sink, self.exit_frame(client_id))?;
            }
            Ok(())
        })();

        if result.is_err() {
            self.clients.lock().unwrap().remove(client_id);
        }
        result
    }

    fn write(&self, client_id: &str, data: &[u8]) -> Result<(), TerminalError> {
        self.ensure_client(client_id)?;
        if data.is_empty() {
            return Ok(());
        }
        self.pty
            .lock()
            .unwrap()
            .write(data)
            .map_err(|error| TerminalError::Io(error.to_string()))
    }

    fn resize(&self, client_id: &str, columns: u32, rows: u32) -> Result<(), TerminalError> {
        self.ensure_client(client_id)?;
        let columns =
            u16::try_from(columns).map_err(|_| TerminalError::Invalid("columns".to_string()))?;
        let rows = u16::try_from(rows).map_err(|_| TerminalError::Invalid("rows".to_string()))?;
        self.pty
            .lock()
            .unwrap()
            .resize(columns, rows)
            .map_err(|error| TerminalError::Io(error.to_string()))
    }

    fn detach(&self, client_id: &str) {
        self.clients.lock().unwrap().remove(client_id);
    }

    fn ensure_client(&self, client_id: &str) -> Result<(), TerminalError> {
        if self.clients.lock().unwrap().contains_key(client_id) {
            Ok(())
        } else {
            Err(TerminalError::ClientNotAttached)
        }
    }

    fn publish_data(&self, data: &[u8]) {
        let _guard = self.publish.lock().unwrap();
        let chunks = self.replay.lock().unwrap().push(data);
        for chunk in chunks {
            self.broadcast(TerminalFrame::data(
                &self.id,
                "",
                chunk.sequence,
                chunk.data,
            ));
        }
    }

    fn publish_exit(&self, exit_code: i32) {
        if self.closed.swap(true, Ordering::SeqCst) {
            return;
        }
        self.exit_code.store(exit_code, Ordering::SeqCst);
        let _guard = self.publish.lock().unwrap();
        let mut frame = self.exit_frame("");
        frame.sequence = 0;
        self.broadcast(frame);
    }

    fn exit_frame(&self, client_id: &str) -> TerminalFrame {
        TerminalFrame {
            frame_type: TerminalFrameType::Exit,
            session_id: self.id.clone(),
            client_id: if client_id.is_empty() {
                None
            } else {
                Some(client_id.to_string())
            },
            exit_code: self.exit_code.load(Ordering::SeqCst),
            ..TerminalFrame::default()
        }
    }

    fn broadcast(&self, frame: TerminalFrame) {
        let clients = {
            let guard = self.clients.lock().unwrap();
            guard
                .iter()
                .map(|(client_id, sender)| (client_id.clone(), sender.clone()))
                .collect::<Vec<_>>()
        };
        let mut stale = Vec::new();
        for (client_id, sender) in clients {
            let mut frame = frame.clone();
            frame.client_id = Some(client_id.clone());
            if matches!(
                sender.try_send(frame),
                Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_))
            ) {
                stale.push(client_id);
            }
        }
        if !stale.is_empty() {
            let mut guard = self.clients.lock().unwrap();
            for client_id in stale {
                guard.remove(&client_id);
            }
        }
    }
}

fn send(sink: &SyncSender<TerminalFrame>, frame: TerminalFrame) -> Result<(), TerminalError> {
    sink.try_send(frame).map_err(|error| match error {
        TrySendError::Full(_) => TerminalError::SlowClient,
        TrySendError::Disconnected(_) => TerminalError::ClientNotAttached,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TerminalError {
    Invalid(String),
    Lease(LeaseError),
    SessionNotFound,
    TooManyClients,
    SlowClient,
    ClientNotAttached,
    Spawn(String),
    Io(String),
}

impl fmt::Display for TerminalError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(field) => write!(formatter, "InvalidTerminalRequest: {field}"),
            Self::Lease(error) => write!(formatter, "{error}"),
            Self::SessionNotFound => write!(formatter, "TerminalSessionMissing: no such session"),
            Self::TooManyClients => {
                write!(formatter, "TerminalBusy: the attachment limit was reached")
            }
            Self::SlowClient => write!(
                formatter,
                "TerminalSlowClient: the client is not reading output"
            ),
            Self::ClientNotAttached => write!(
                formatter,
                "TerminalNotAttached: attach before using the session"
            ),
            Self::Spawn(error) => write!(formatter, "TerminalSpawnFailed: {error}"),
            Self::Io(error) => write!(formatter, "TerminalIoFailed: {error}"),
        }
    }
}

impl std::error::Error for TerminalError {}

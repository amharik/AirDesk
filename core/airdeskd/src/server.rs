use std::fs;
use std::io::{self, BufReader};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::mpsc::sync_channel;
use std::sync::Arc;
use std::thread;

use crate::frame::{FrameError, TerminalFrame};
use crate::session::Daemon;

pub fn serve_unix(path: &Path, daemon: Arc<Daemon>) -> io::Result<()> {
    if path.exists() {
        fs::remove_file(path)?;
    }
    let listener = UnixListener::bind(path)?;
    for connection in listener.incoming() {
        match connection {
            Ok(stream) => {
                let daemon = daemon.clone();
                thread::spawn(move || {
                    if let Err(error) = handle_connection(stream, daemon) {
                        eprintln!("airdeskd connection failed: {error}");
                    }
                });
            }
            Err(error) => eprintln!("airdeskd accept failed: {error}"),
        }
    }
    Ok(())
}

pub fn handle_connection(stream: UnixStream, daemon: Arc<Daemon>) -> io::Result<()> {
    let writer = stream.try_clone()?;
    let (sender, receiver) = sync_channel::<TerminalFrame>(256);
    let writer_thread = thread::spawn(move || {
        let mut writer = writer;
        while let Ok(frame) = receiver.recv() {
            if frame.write_to(&mut writer).is_err() {
                break;
            }
        }
    });

    let mut reader = BufReader::new(stream);
    let mut client_id = None;
    loop {
        match TerminalFrame::read_from(&mut reader) {
            Ok(frame) => {
                if frame.client_id.is_some() {
                    client_id = frame.client_id.clone();
                }
                if let Err(error) = daemon.handle(frame.clone(), sender.clone()) {
                    let _ = sender.try_send(TerminalFrame::error(
                        frame.session_id,
                        frame.client_id,
                        error.to_string(),
                    ));
                }
            }
            Err(FrameError::Closed) => break,
            Err(error) => {
                let _ = sender.try_send(TerminalFrame::error(
                    "unknown",
                    client_id.clone(),
                    error.to_string(),
                ));
                break;
            }
        }
    }

    if let Some(client_id) = client_id {
        daemon.detach_client(&client_id);
    }
    drop(sender);
    let _ = writer_thread.join();
    Ok(())
}

use std::ffi::CString;
use std::io::{self, Read};
use std::os::fd::FromRawFd;
use std::os::unix::io::RawFd;
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::thread;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PtyConfig {
    pub program: String,
    pub args: Vec<String>,
    pub columns: u16,
    pub rows: u16,
}

impl PtyConfig {
    pub fn shell(program: impl Into<String>, args: Vec<String>, columns: u16, rows: u16) -> Self {
        Self {
            program: program.into(),
            args,
            columns: columns.max(1),
            rows: rows.max(1),
        }
    }
}

pub trait PtyHandle: Send {
    fn write(&mut self, data: &[u8]) -> io::Result<()>;
    fn resize(&mut self, columns: u16, rows: u16) -> io::Result<()>;
    fn close(&mut self);
}

pub struct SpawnedPty {
    pub handle: Box<dyn PtyHandle>,
    pub output: Receiver<Vec<u8>>,
    pub exit: Receiver<i32>,
}

pub trait PtySpawner: Send + Sync {
    fn spawn(&self, config: &PtyConfig) -> io::Result<SpawnedPty>;
}

#[derive(Debug, Clone, Copy, Default)]
pub struct UnixPtySpawner;

impl PtySpawner for UnixPtySpawner {
    fn spawn(&self, config: &PtyConfig) -> io::Result<SpawnedPty> {
        UnixPty::spawn(config)
    }
}

struct UnixPty {
    master: RawFd,
    pid: libc::pid_t,
}

impl PtyHandle for UnixPty {
    fn write(&mut self, data: &[u8]) -> io::Result<()> {
        let mut offset = 0;
        while offset < data.len() {
            let written = unsafe {
                libc::write(
                    self.master,
                    data[offset..].as_ptr() as *const libc::c_void,
                    data.len() - offset,
                )
            };
            if written < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if written == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::WriteZero,
                    "PTY write returned zero",
                ));
            }
            offset += written as usize;
        }
        Ok(())
    }

    fn resize(&mut self, columns: u16, rows: u16) -> io::Result<()> {
        let size = libc::winsize {
            ws_row: rows.max(1),
            ws_col: columns.max(1),
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let result = unsafe { libc::ioctl(self.master, libc::TIOCSWINSZ, &size) };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    fn close(&mut self) {
        if self.master >= 0 {
            unsafe {
                libc::kill(-self.pid, libc::SIGHUP);
                libc::close(self.master);
            }
            self.master = -1;
        }
    }
}

impl Drop for UnixPty {
    fn drop(&mut self) {
        self.close();
    }
}

impl UnixPty {
    fn spawn(config: &PtyConfig) -> io::Result<SpawnedPty> {
        let program = CString::new(config.program.as_bytes())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid program"))?;
        let mut arguments = Vec::with_capacity(config.args.len() + 2);
        arguments.push(program.clone());
        for argument in &config.args {
            arguments
                .push(CString::new(argument.as_bytes()).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "invalid argument")
                })?);
        }
        let mut argument_pointers: Vec<*const libc::c_char> =
            arguments.iter().map(|argument| argument.as_ptr()).collect();
        argument_pointers.push(std::ptr::null());

        let mut master: libc::c_int = -1;
        let mut slave: libc::c_int = -1;
        let mut size = libc::winsize {
            ws_row: config.rows,
            ws_col: config.columns,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        let result = unsafe {
            libc::openpty(
                &mut master,
                &mut slave,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                &mut size,
            )
        };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }

        let pid = unsafe { libc::fork() };
        if pid < 0 {
            let error = io::Error::last_os_error();
            unsafe {
                libc::close(master);
                libc::close(slave);
            }
            return Err(error);
        }
        if pid == 0 {
            unsafe {
                libc::close(master);
                libc::setsid();
                libc::ioctl(slave, libc::TIOCSCTTY as _, 0);
                libc::dup2(slave, libc::STDIN_FILENO);
                libc::dup2(slave, libc::STDOUT_FILENO);
                libc::dup2(slave, libc::STDERR_FILENO);
                if slave > libc::STDERR_FILENO {
                    libc::close(slave);
                }
                libc::execvp(program.as_ptr(), argument_pointers.as_ptr());
                libc::_exit(127);
            }
        }

        unsafe {
            libc::close(slave);
        }

        let reader_fd = unsafe { libc::dup(master) };
        if reader_fd < 0 {
            let error = io::Error::last_os_error();
            unsafe {
                libc::close(master);
                libc::kill(pid, libc::SIGKILL);
            }
            return Err(error);
        }

        let (output_tx, output_rx) = sync_channel::<Vec<u8>>(128);
        let (exit_tx, exit_rx) = sync_channel::<i32>(1);
        spawn_reader(reader_fd, output_tx);
        spawn_waiter(pid, exit_tx);

        Ok(SpawnedPty {
            handle: Box::new(UnixPty { master, pid }),
            output: output_rx,
            exit: exit_rx,
        })
    }
}

fn spawn_reader(fd: RawFd, sender: SyncSender<Vec<u8>>) {
    thread::spawn(move || {
        let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
        let mut buffer = vec![0u8; 8192];
        loop {
            match file.read(&mut buffer) {
                Ok(0) => break,
                Ok(count) => {
                    if sender.send(buffer[..count].to_vec()).is_err() {
                        break;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    });
}

fn spawn_waiter(pid: libc::pid_t, sender: SyncSender<i32>) {
    thread::spawn(move || {
        let mut status = 0;
        loop {
            let result = unsafe { libc::waitpid(pid, &mut status, 0) };
            if result == pid {
                let code = if libc::WIFEXITED(status) {
                    libc::WEXITSTATUS(status)
                } else if libc::WIFSIGNALED(status) {
                    128 + libc::WTERMSIG(status)
                } else {
                    -1
                };
                let _ = sender.send(code);
                break;
            }
            if result < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                let _ = sender.send(-1);
                break;
            }
        }
    });
}

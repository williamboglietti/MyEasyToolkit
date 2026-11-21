use std::{
    fmt::Write as _,
    io::{self, Read, Write},
    net::{Ipv4Addr, TcpListener, TcpStream},
    process::Command,
    sync::mpsc::{self, RecvTimeoutError, Sender},
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
use url::Url;

const PROOF_BYTES: usize = 64;
const LOCAL_TIMEOUT: Duration = Duration::from_secs(1);

pub(super) enum IssueError {
    Authentication,
    Unavailable,
}

pub(super) fn is_mystorage_bootstrap(url: &Url) -> bool {
    matches!(
        url.as_str(),
        "https://mystorage.ovh/post-installation/windows/00-bootstrap.ps1"
            | "https://mystorage.ovh/post-installation/linux/00-bootstrap.sh"
            | "https://mystorage.ovh/post-installation/linux/04-enregistrer-machine.sh"
    )
}

pub(super) struct Broker {
    port: u16,
    proof: String,
    stop: Sender<()>,
    worker: Option<JoinHandle<()>>,
}

impl Broker {
    pub(super) fn start(
        issue: impl FnOnce() -> Result<String, IssueError> + Send + 'static,
    ) -> Result<Self, String> {
        let mut random = [0_u8; 32];
        getrandom::fill(&mut random)
            .map_err(|_| "Impossible de protéger le jeton MyStorage.".to_owned())?;
        let mut proof = String::with_capacity(PROOF_BYTES);
        for byte in random {
            write!(&mut proof, "{byte:02x}").expect("writing to a String is infallible");
        }
        let mut expected = [0_u8; PROOF_BYTES + 1];
        expected[..PROOF_BYTES].copy_from_slice(proof.as_bytes());
        expected[PROOF_BYTES] = b'\n';

        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).map_err(local_error)?;
        listener.set_nonblocking(true).map_err(local_error)?;
        let port = listener.local_addr().map_err(local_error)?.port();
        let (stop, stopped) = mpsc::channel();

        let worker = thread::Builder::new()
            .spawn(move || loop {
                match listener.accept() {
                    Ok((mut connection, _)) => {
                        if connection.set_nonblocking(false).is_ok()
                            && read_proof(&mut connection).as_ref() == Some(&expected)
                        {
                            let response = issue();
                            let message = match &response {
                                Ok(token) => token,
                                Err(IssueError::Authentication) => "AUTH",
                                Err(IssueError::Unavailable) => "UNAVAILABLE",
                            };
                            let _ = connection.set_write_timeout(Some(LOCAL_TIMEOUT));
                            let _ = writeln!(connection, "{message}");
                            return;
                        }
                    }
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
                    Err(_) => return,
                }
                if stopped.recv_timeout(Duration::from_millis(25)) != Err(RecvTimeoutError::Timeout)
                {
                    return;
                }
            })
            .map_err(local_error)?;
        Ok(Self {
            port,
            proof,
            stop,
            worker: Some(worker),
        })
    }

    pub(super) fn configure(&self, command: &mut Command) {
        command.env("MYSTORAGE_ENROLL_PORT", self.port.to_string());
        command.env("MYSTORAGE_ENROLL_PROOF", &self.proof);
    }
}

impl Drop for Broker {
    fn drop(&mut self) {
        let _ = self.stop.send(());
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

fn local_error(error: io::Error) -> String {
    format!("Connexion locale MyStorage indisponible : {error}")
}

fn read_proof(connection: &mut TcpStream) -> Option<[u8; PROOF_BYTES + 1]> {
    let mut buffer = [0_u8; PROOF_BYTES + 1];
    let mut offset = 0;
    let deadline = Instant::now() + LOCAL_TIMEOUT;
    while offset < buffer.len() {
        let left = deadline.checked_duration_since(Instant::now())?;
        connection.set_read_timeout(Some(left)).ok()?;
        let count = connection.read(&mut buffer[offset..]).ok()?;
        if count == 0 {
            return None;
        }
        offset += count;
    }
    Some(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;
    use portable_pty::{native_pty_system, PtySize};
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };

    #[test]
    fn only_the_bootstraps_on_the_exact_mystorage_url_can_request_enrollment() {
        for url in [
            "https://mystorage.ovh/post-installation/windows/00-bootstrap.ps1",
            "https://mystorage.ovh/post-installation/linux/00-bootstrap.sh",
            "https://mystorage.ovh/post-installation/linux/04-enregistrer-machine.sh",
        ] {
            assert!(is_mystorage_bootstrap(&Url::parse(url).unwrap()));
        }
        for url in [
            "http://mystorage.ovh/post-installation/windows/00-bootstrap.ps1",
            "https://mystorage.ovh.example/post-installation/windows/00-bootstrap.ps1",
            "https://mystorage.ovh:404/post-installation/linux/00-bootstrap.sh",
            "https://mystorage.ovh/post-installation/linux/00-bootstrap.sh?x=1",
            "https://mystorage.ovh/post-installation/linux/02-acces-automation.sh",
            "file:///post-installation/linux/00-bootstrap.sh",
        ] {
            assert!(!is_mystorage_bootstrap(&Url::parse(url).unwrap()));
        }
    }

    #[test]
    fn issues_only_on_demand_to_the_child_holding_the_proof() {
        let calls = Arc::new(AtomicUsize::new(0));
        let observed = Arc::clone(&calls);
        let token = "met_enroll_".to_string() + &"t".repeat(43);
        let issued = token.clone();
        let broker = Broker::start(move || {
            observed.fetch_add(1, Ordering::SeqCst);
            Ok(issued)
        })
        .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        let address = (Ipv4Addr::LOCALHOST, broker.port);
        let request = |proof: &str| {
            let mut stream = TcpStream::connect(address).unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            writeln!(stream, "{proof}").unwrap();
            let mut response = String::new();
            stream.read_to_string(&mut response).unwrap();
            response
        };
        assert!(request(&"z".repeat(PROOF_BYTES)).is_empty());
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(request(&broker.proof), format!("{token}\n"));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        drop(broker);
        assert!(TcpStream::connect(address).is_err());
    }

    #[test]
    fn closing_the_process_without_registration_uses_no_token() {
        let broker = Broker::start(|| panic!("an idle bootstrap must not issue a token")).unwrap();
        let address = (Ipv4Addr::LOCALHOST, broker.port);
        drop(broker);
        assert!(TcpStream::connect(address).is_err());
    }

    #[test]
    fn enrollment_proof_reaches_an_actual_terminal_child() {
        let broker = Broker::start(|| Err(IssueError::Authentication)).unwrap();
        let mut command = Command::new(std::env::current_exe().unwrap());
        command.args(["--exact", "enrollment::tests::terminal_child_fixture"]);
        command.env("MET_TEST_ENROLLMENT_CHILD", "1");
        broker.configure(&mut command);

        let terminal = native_pty_system().openpty(PtySize::default()).unwrap();
        let mut child = terminal
            .slave
            .spawn_command(crate::console::pty_command(&command))
            .unwrap();
        drop(terminal.slave);
        let mut output = terminal.master.try_clone_reader().unwrap();
        let drain = thread::spawn(move || io::copy(&mut output, &mut io::sink()));
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                assert!(status.success());
                break;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                panic!("terminal enrollment fixture did not exit");
            }
            thread::sleep(Duration::from_millis(25));
        }
        drop(terminal.master);
        let _ = drain.join();
    }

    #[test]
    fn terminal_child_fixture() {
        if std::env::var_os("MET_TEST_ENROLLMENT_CHILD").is_none() {
            return;
        }
        let port = std::env::var("MYSTORAGE_ENROLL_PORT")
            .unwrap()
            .parse()
            .unwrap();
        let proof = std::env::var("MYSTORAGE_ENROLL_PROOF").unwrap();
        let mut stream = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        writeln!(stream, "{proof}").unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        assert_eq!(response, "AUTH\n");
    }
}

use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::{
    io::{Read, Write},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

fn run_interactive_failure(batch: bool) {
    let directory = tempfile::tempdir().unwrap();
    let (filename, script) = if cfg!(windows) {
        ("test.ps1", "$answer = Read-Host 'REPONSE?'\n[Console]::Error.WriteLine(\"ERREUR: $answer\")\nexit 1\n")
    } else {
        ("test.sh", "#!/usr/bin/env bash\nprintf 'REPONSE? '\nread -r answer\nprintf 'ERREUR: %s\\n' \"$answer\" >&2\nexit 1\n")
    };
    std::fs::write(directory.path().join(filename), script).unwrap();
    let pty = native_pty_system()
        .openpty(PtySize {
            rows: 30,
            cols: 100,
            pixel_width: 0,
            pixel_height: 0,
        })
        .unwrap();
    let mut command = CommandBuilder::new(env!("CARGO_BIN_EXE_myeasytoolkit"));
    command.cwd(directory.path());
    command.env("TERM", "xterm-256color");
    let mut child = pty.slave.spawn_command(command).unwrap();
    drop(pty.slave);
    let mut reader = pty.master.try_clone_reader().unwrap();
    let mut writer = pty.master.take_writer().unwrap();
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let mut buf = [0; 8192];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    let mut screen = vt100::Parser::new(30, 100, 1000);
    let mut wait_for = |text: &str| -> String {
        let deadline = Instant::now() + Duration::from_secs(15);
        while Instant::now() < deadline {
            if screen.screen().contents().contains(text) {
                return screen.screen().contents();
            }
            if let Ok(bytes) = rx.recv_timeout(Duration::from_millis(100)) {
                screen.process(&bytes);
            }
        }
        panic!(
            "'{text}' absent de l'écran : {}",
            screen.screen().contents()
        );
    };
    wait_for(filename);
    if batch {
        writer.write_all(b"\r x").unwrap();
        wait_for("Confirmer la sélection");
    } else {
        writer.write_all(b"\r\r").unwrap();
        wait_for("Exécuter");
    }
    writer.write_all(b"o").unwrap();
    let console = wait_for("REPONSE?");
    assert!(
        !console.contains("Confirmer la sélection"),
        "La confirmation reste affichée : {console}"
    );
    assert!(
        !console.contains("[Annuler]"),
        "Les anciens boutons restent affichés : {console}"
    );
    writer.write_all(b"bonjour\r").unwrap();
    wait_for("ERREUR: bonjour");
    wait_for("Échec (code 1)");
    writer.write_all(b"\r").unwrap();
    wait_for("code de sortie");
    writer.write_all(b"\rq").unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success());
            return;
        }
        thread::sleep(Duration::from_millis(50));
    }
    let _ = child.kill();
    panic!("L'application ne s'est pas fermée");
}

#[test]
fn single_script_has_a_clean_console() {
    run_interactive_failure(false);
}

#[test]
fn batch_script_has_a_clean_console() {
    run_interactive_failure(true);
}

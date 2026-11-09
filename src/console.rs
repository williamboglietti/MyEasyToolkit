//! Interactive script console. Output stays in the application's alternate screen.
use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Terminal,
};
use std::{
    io::{self, Read, Write},
    process::Command,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

const HISTORY_LINES: usize = 10_000;

fn key_bytes(key: KeyEvent, application_cursor: bool) -> Vec<u8> {
    if key.modifiers.contains(KeyModifiers::CONTROL) {
        if let KeyCode::Char(c) = key.code {
            let lower = c.to_ascii_lowercase();
            if lower.is_ascii_lowercase() {
                return vec![lower as u8 - b'a' + 1];
            }
        }
    }
    if application_cursor {
        let suffix = match key.code {
            KeyCode::Up => Some('A'),
            KeyCode::Down => Some('B'),
            KeyCode::Right => Some('C'),
            KeyCode::Left => Some('D'),
            _ => None,
        };
        if let Some(suffix) = suffix {
            return format!("\x1bO{suffix}").into_bytes();
        }
    }
    let sequence = match key.code {
        KeyCode::Enter => "\r",
        KeyCode::Backspace => "\x7f",
        KeyCode::Tab => "\t",
        KeyCode::BackTab => "\x1b[Z",
        KeyCode::Esc => "\x1b",
        KeyCode::Up => "\x1b[A",
        KeyCode::Down => "\x1b[B",
        KeyCode::Right => "\x1b[C",
        KeyCode::Left => "\x1b[D",
        KeyCode::Home => "\x1b[H",
        KeyCode::End => "\x1b[F",
        KeyCode::Delete => "\x1b[3~",
        KeyCode::Insert => "\x1b[2~",
        KeyCode::PageUp => "\x1b[5~",
        KeyCode::PageDown => "\x1b[6~",
        KeyCode::F(1) => "\x1bOP",
        KeyCode::F(2) => "\x1bOQ",
        KeyCode::F(3) => "\x1bOR",
        KeyCode::F(4) => "\x1bOS",
        KeyCode::F(5) => "\x1b[15~",
        KeyCode::F(6) => "\x1b[17~",
        KeyCode::F(7) => "\x1b[18~",
        KeyCode::F(8) => "\x1b[19~",
        KeyCode::F(9) => "\x1b[20~",
        KeyCode::F(10) => "\x1b[21~",
        KeyCode::F(11) => "\x1b[23~",
        KeyCode::F(12) => "\x1b[24~",
        KeyCode::Char(c) => {
            let mut out = Vec::new();
            if key.modifiers.contains(KeyModifiers::ALT) {
                out.push(0x1b);
            }
            let mut buffer = [0; 4];
            out.extend_from_slice(c.encode_utf8(&mut buffer).as_bytes());
            return out;
        }
        _ => return Vec::new(),
    };
    sequence.as_bytes().to_vec()
}

fn mouse_bytes(mouse: MouseEvent, screen: &vt100::Screen) -> Option<Vec<u8>> {
    use vt100::{MouseProtocolEncoding as Encoding, MouseProtocolMode as Mode};
    let mode = screen.mouse_protocol_mode();
    if mode == Mode::None {
        return None;
    }
    let (rows, cols) = screen.size();
    let x = mouse.column.checked_sub(1)?;
    let y = mouse.row.checked_sub(2)?;
    if x >= cols || y >= rows {
        return None;
    }
    let button = |button| match button {
        MouseButton::Left => 0,
        MouseButton::Middle => 1,
        MouseButton::Right => 2,
    };
    let (mut code, release) = match mouse.kind {
        MouseEventKind::Down(b) => (button(b), false),
        MouseEventKind::Up(b) if mode != Mode::Press => (button(b), true),
        MouseEventKind::Drag(b) if matches!(mode, Mode::ButtonMotion | Mode::AnyMotion) => {
            (button(b) + 32, false)
        }
        MouseEventKind::Moved if mode == Mode::AnyMotion => (35, false),
        MouseEventKind::ScrollUp => (64, false),
        MouseEventKind::ScrollDown => (65, false),
        _ => return None,
    };
    if mouse.modifiers.contains(KeyModifiers::SHIFT) {
        code += 4;
    }
    if mouse.modifiers.contains(KeyModifiers::ALT) {
        code += 8;
    }
    if mouse.modifiers.contains(KeyModifiers::CONTROL) {
        code += 16;
    }
    let (x, y) = (u32::from(x) + 1, u32::from(y) + 1);
    match screen.mouse_protocol_encoding() {
        Encoding::Sgr => {
            Some(format!("\x1b[<{code};{x};{y}{}", if release { 'm' } else { 'M' }).into_bytes())
        }
        encoding => {
            if release {
                code = 3;
            }
            let mut output = b"\x1b[M".to_vec();
            for value in [code + 32, x + 32, y + 32] {
                if encoding == Encoding::Default {
                    output.push(u8::try_from(value).ok()?);
                } else {
                    let mut buf = [0; 4];
                    output
                        .extend_from_slice(char::from_u32(value)?.encode_utf8(&mut buf).as_bytes());
                }
            }
            Some(output)
        }
    }
}

fn size() -> io::Result<PtySize> {
    let (cols, rows) = crossterm::terminal::size()?;
    Ok(PtySize {
        rows: rows.saturating_sub(5).max(1),
        cols: cols.saturating_sub(2).max(1),
        pixel_width: 0,
        pixel_height: 0,
    })
}

fn color(color: vt100::Color) -> Color {
    match color {
        vt100::Color::Default => Color::Reset,
        vt100::Color::Idx(n) => Color::Indexed(n),
        vt100::Color::Rgb(r, g, b) => Color::Rgb(r, g, b),
    }
}

fn render(screen: &vt100::Screen) -> Vec<Line<'static>> {
    let (rows, cols) = screen.size();
    (0..rows)
        .map(|row| {
            let mut spans = Vec::new();
            for col in 0..cols {
                let Some(cell) = screen.cell(row, col) else {
                    continue;
                };
                if cell.is_wide_continuation() {
                    continue;
                }
                let mut style = Style::default()
                    .fg(color(cell.fgcolor()))
                    .bg(color(cell.bgcolor()));
                if cell.bold() {
                    style = style.add_modifier(Modifier::BOLD);
                }
                if cell.italic() {
                    style = style.add_modifier(Modifier::ITALIC);
                }
                if cell.underline() {
                    style = style.add_modifier(Modifier::UNDERLINED);
                }
                if cell.inverse() {
                    style = style.add_modifier(Modifier::REVERSED);
                }
                spans.push(Span::styled(
                    if cell.has_contents() {
                        cell.contents()
                    } else {
                        " ".to_owned()
                    },
                    style,
                ));
            }
            Line::from(spans)
        })
        .collect()
}

pub fn run(
    name: &str,
    command: &Command,
    wait_for_user: bool,
    pause_on_error: bool,
) -> Result<(), String> {
    run_inner(name, command, wait_for_user, pause_on_error).map_err(|e| format!("Console : {e}"))?
}

fn run_inner(
    name: &str,
    command: &Command,
    wait_for_user: bool,
    pause_on_error: bool,
) -> io::Result<Result<(), String>> {
    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let mut dimensions = size()?;
    let pair = native_pty_system()
        .openpty(dimensions)
        .map_err(io::Error::other)?;
    let mut builder = CommandBuilder::new(command.get_program());
    builder.args(command.get_args());
    if let Some(dir) = command.get_current_dir() {
        builder.cwd(dir);
    }
    let mut child = pair
        .slave
        .spawn_command(builder)
        .map_err(io::Error::other)?;
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().map_err(io::Error::other)?;
    let mut writer = pair.master.take_writer().map_err(io::Error::other)?;
    let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(128);
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    let mut parser = vt100::Parser::new(dimensions.rows, dimensions.cols, HISTORY_LINES);
    let mut completed = None;
    let mut completed_at = None;
    let result = (|| -> io::Result<Result<(), String>> {
        loop {
            let mut disconnected = false;
            let mut queue_empty = false;
            for _ in 0..128 {
                match rx.try_recv() {
                    Ok(bytes) => {
                        parser.process(&bytes);
                    }
                    Err(mpsc::TryRecvError::Empty) => {
                        queue_empty = true;
                        break;
                    }
                    Err(mpsc::TryRecvError::Disconnected) => {
                        disconnected = true;
                        break;
                    }
                }
            }
            if completed.is_none() {
                completed = child.try_wait()?;
                if completed.is_some() {
                    completed_at = Some(Instant::now());
                }
            }
            let drained = completed.is_some()
                && (disconnected
                    || (queue_empty
                        && completed_at
                            .is_some_and(|at| at.elapsed() >= Duration::from_millis(500))));
            if drained
                && !wait_for_user
                && (!pause_on_error || completed.as_ref().is_some_and(|s| s.success()))
            {
                let status = completed.as_ref().expect("drained implies completion");
                return Ok(if status.success() {
                    Ok(())
                } else {
                    Err(format!("code de sortie : {}", status.exit_code()))
                });
            }
            terminal.draw(|frame| {
                let area = frame.area();
                let parts = Layout::default()
                    .direction(Direction::Vertical)
                    .constraints([
                        Constraint::Length(1),
                        Constraint::Min(3),
                        Constraint::Length(2),
                    ])
                    .split(area);
                frame.render_widget(
                    Paragraph::new(format!(" MyEasyToolkit  /  Exécution  /  {name}")).style(
                        Style::default()
                            .fg(Color::Cyan)
                            .add_modifier(Modifier::BOLD),
                    ),
                    parts[0],
                );
                let block = Block::default().title(" Console ").borders(Borders::ALL);
                let inner = block.inner(parts[1]);
                frame.render_widget(
                    Paragraph::new(render(parser.screen())).block(block),
                    parts[1],
                );
                if !drained && parser.screen().scrollback() == 0 && !parser.screen().hide_cursor() {
                    let (row, col) = parser.screen().cursor_position();
                    if row < inner.height && col < inner.width {
                        frame.set_cursor_position((inner.x + col, inner.y + row));
                    }
                }
                let status = if let Some(status) = completed.as_ref().filter(|_| drained) {
                    format!(
                        "{}  ·  Entrée ou clic pour revenir  ·  Molette/PgUp/PgDn : historique",
                        if status.success() {
                            "Terminé".into()
                        } else {
                            format!("Échec (code {})", status.exit_code())
                        }
                    )
                } else {
                    "En cours  ·  Saisissez vos réponses dans la console  ·  Ctrl+C : interrompre"
                        .into()
                };
                frame.render_widget(
                    Paragraph::new(status).style(Style::default().fg(
                        if completed.as_ref().is_some_and(|s| !s.success()) {
                            Color::Red
                        } else {
                            Color::Gray
                        },
                    )),
                    parts[2],
                );
            })?;
            if !event::poll(Duration::from_millis(50))? {
                continue;
            }
            match event::read()? {
                Event::Resize(_, _) => {
                    let new_size = size()?;
                    pair.master.resize(new_size).map_err(io::Error::other)?;
                    parser.set_size(new_size.rows, new_size.cols);
                    dimensions = new_size;
                    terminal.clear()?;
                }
                Event::Key(key) if key.kind == KeyEventKind::Press => {
                    if drained && matches!(key.code, KeyCode::Enter | KeyCode::Esc) {
                        break;
                    }
                    match key.code {
                        KeyCode::PageUp
                            if drained || key.modifiers.contains(KeyModifiers::SHIFT) =>
                        {
                            parser.set_scrollback(
                                parser
                                    .screen()
                                    .scrollback()
                                    .saturating_add(usize::from(dimensions.rows)),
                            )
                        }
                        KeyCode::PageDown
                            if drained || key.modifiers.contains(KeyModifiers::SHIFT) =>
                        {
                            parser.set_scrollback(
                                parser
                                    .screen()
                                    .scrollback()
                                    .saturating_sub(usize::from(dimensions.rows)),
                            )
                        }
                        _ if completed.is_none() => {
                            parser.set_scrollback(0);
                            writer
                                .write_all(&key_bytes(key, parser.screen().application_cursor()))?;
                            writer.flush()?;
                        }
                        _ => {}
                    }
                }
                Event::Paste(text) if completed.is_none() => {
                    parser.set_scrollback(0);
                    if parser.screen().bracketed_paste() {
                        writer.write_all(b"\x1b[200~")?;
                    }
                    writer.write_all(text.as_bytes())?;
                    if parser.screen().bracketed_paste() {
                        writer.write_all(b"\x1b[201~")?;
                    }
                    writer.flush()?;
                }
                Event::Mouse(mouse)
                    if completed.is_none()
                        && parser.screen().mouse_protocol_mode()
                            != vt100::MouseProtocolMode::None =>
                {
                    if let Some(bytes) = mouse_bytes(mouse, parser.screen()) {
                        writer.write_all(&bytes)?;
                        writer.flush()?;
                    }
                }
                Event::Mouse(mouse) => match mouse.kind {
                    MouseEventKind::ScrollUp => {
                        parser.set_scrollback(parser.screen().scrollback().saturating_add(3))
                    }
                    MouseEventKind::ScrollDown => {
                        parser.set_scrollback(parser.screen().scrollback().saturating_sub(3))
                    }
                    MouseEventKind::Down(_) if drained => break,
                    _ => {}
                },
                _ => {}
            }
        }
        let status = completed.expect("a completed script is needed to close the console");
        Ok(if status.success() {
            Ok(())
        } else {
            Err(format!("code de sortie : {}", status.exit_code()))
        })
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn input_encodes_navigation_control_and_unicode() {
        assert_eq!(
            key_bytes(
                KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL),
                false
            ),
            b"\x03"
        );
        assert_eq!(
            key_bytes(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE), false),
            b"\x1b[A"
        );
        assert_eq!(
            key_bytes(KeyEvent::new(KeyCode::Char('é'), KeyModifiers::NONE), false),
            "é".as_bytes()
        );
    }
    #[test]
    fn terminal_keeps_output_and_scrollback() {
        let mut parser = vt100::Parser::new(2, 30, HISTORY_LINES);
        parser.process(b"first\r\nsecond\r\nerror\r\n");
        assert!(parser.screen().contents().contains("error"));
        parser.set_scrollback(2);
        assert!(parser.screen().contents().contains("first"));
    }
}

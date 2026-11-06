mod repository;

use crossterm::{
    event::{
        self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyModifiers,
        MouseEventKind,
    },
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame, Terminal,
};
use repository::{normalize_url, parse_listing, Entry, FetchError, Repository};
use std::{
    io::{self, Write},
    process::Command,
};
use url::Url;

#[derive(Clone)]
enum Action {
    Open(Url),
    OpenRoot(Url),
    Run(Entry),
}
enum Mode {
    Url,
    Browsing,
    Username(Action),
    Password(Action, String),
    Confirm(Entry),
    Message,
}
struct App {
    repo: Repository,
    root: Option<Url>,
    current: Option<Url>,
    entries: Vec<Entry>,
    state: ListState,
    mode: Mode,
    input: String,
    message: String,
}
impl App {
    fn new() -> Result<Self, String> {
        Ok(Self {
            repo: Repository::new()?,
            root: None,
            current: None,
            entries: vec![],
            state: ListState::default(),
            mode: Mode::Url,
            input: String::new(),
            message: String::new(),
        })
    }
    fn action(&mut self, action: Action) {
        let url = match &action {
            Action::Open(url) | Action::OpenRoot(url) => url,
            Action::Run(entry) => &entry.url,
        };
        let is_new_root = matches!(action, Action::OpenRoot(_));
        match self.repo.fetch(url) {
            Ok(data) => match action {
                Action::Open(url) | Action::OpenRoot(url) => {
                    let html = String::from_utf8_lossy(&data);
                    self.entries = parse_listing(&url, &html);
                    self.current = Some(url.clone());
                    if is_new_root || self.root.is_none() {
                        self.root = Some(url);
                    }
                    self.state.select((!self.entries.is_empty()).then_some(0));
                    self.mode = Mode::Browsing;
                }
                Action::Run(entry) => {
                    self.mode = Mode::Browsing;
                    if let Err(e) = run_script(&entry, &data) {
                        self.error(e);
                    }
                }
            },
            Err(FetchError::Unauthorized) => {
                self.input.clear();
                self.mode = Mode::Username(action);
            }
            Err(FetchError::Message(e)) => self.error(e),
        }
    }
    fn error(&mut self, message: String) {
        self.message = message;
        self.mode = Mode::Message;
    }
    fn select(&mut self) {
        if let Some(entry) = self
            .state
            .selected()
            .and_then(|i| self.entries.get(i))
            .cloned()
        {
            if entry.directory {
                self.action(Action::Open(entry.url));
            } else if entry.name.to_ascii_lowercase().ends_with(".sh")
                || entry.name.to_ascii_lowercase().ends_with(".ps1")
            {
                self.mode = Mode::Confirm(entry);
            } else {
                self.error("Ce fichier n’est pas un script .sh ou .ps1.".into());
            }
        }
    }
    fn parent(&mut self) {
        if let (Some(current), Some(root)) = (&self.current, &self.root) {
            if current != root {
                if let Ok(url) = current.join("../") {
                    if url.path().starts_with(root.path()) {
                        self.action(Action::Open(url));
                    }
                }
            }
        }
    }
    fn move_selection(&mut self, delta: isize) {
        if !self.entries.is_empty() {
            let old = self.state.selected().unwrap_or(0);
            let next = old.saturating_add_signed(delta).min(self.entries.len() - 1);
            self.state.select(Some(next));
        }
    }
    fn key(&mut self, key: KeyEvent) -> bool {
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return false;
        }
        let mode = std::mem::replace(&mut self.mode, Mode::Browsing);
        match mode {
            Mode::Browsing => match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return false,
                KeyCode::Up | KeyCode::Char('k') => self.move_selection(-1),
                KeyCode::Down | KeyCode::Char('j') => self.move_selection(1),
                KeyCode::Enter | KeyCode::Right => self.select(),
                KeyCode::Backspace | KeyCode::Left => self.parent(),
                KeyCode::Char('r') => {
                    if let Some(url) = self.current.clone() {
                        self.action(Action::Open(url));
                    }
                }
                KeyCode::Char('o') => {
                    self.input.clear();
                    self.mode = Mode::Url;
                }
                _ => {}
            },
            Mode::Url => match key.code {
                KeyCode::Enter => match normalize_url(&self.input) {
                    Ok(url) => {
                        self.input.clear();
                        self.action(Action::OpenRoot(url));
                    }
                    Err(e) => {
                        self.message = e;
                        self.mode = Mode::Url;
                    }
                },
                KeyCode::Esc => {
                    if self.current.is_some() {
                        self.mode = Mode::Browsing;
                    } else {
                        return false;
                    }
                }
                KeyCode::Backspace => {
                    self.input.pop();
                    self.mode = Mode::Url;
                }
                KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.input.push(c);
                    self.mode = Mode::Url;
                }
                _ => self.mode = Mode::Url,
            },
            Mode::Username(action) => match key.code {
                KeyCode::Enter => {
                    let username = std::mem::take(&mut self.input);
                    self.mode = Mode::Password(action, username);
                }
                KeyCode::Esc => {
                    self.input.clear();
                    self.mode = if self.current.is_some() {
                        Mode::Browsing
                    } else {
                        Mode::Url
                    };
                }
                KeyCode::Backspace => {
                    self.input.pop();
                    self.mode = Mode::Username(action);
                }
                KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.input.push(c);
                    self.mode = Mode::Username(action);
                }
                _ => self.mode = Mode::Username(action),
            },
            Mode::Password(action, username) => match key.code {
                KeyCode::Enter => {
                    let password = std::mem::take(&mut self.input);
                    let scope = match &action {
                        Action::Open(url) | Action::OpenRoot(url) => url.clone(),
                        Action::Run(entry) => entry.url.join("./").expect("file URL has a parent"),
                    };
                    self.repo.authenticate(scope, username, password);
                    self.action(action);
                }
                KeyCode::Esc => {
                    self.input.clear();
                    self.mode = if self.current.is_some() {
                        Mode::Browsing
                    } else {
                        Mode::Url
                    };
                }
                KeyCode::Backspace => {
                    self.input.pop();
                    self.mode = Mode::Password(action, username);
                }
                KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.input.push(c);
                    self.mode = Mode::Password(action, username);
                }
                _ => self.mode = Mode::Password(action, username),
            },
            Mode::Confirm(entry) => {
                if matches!(key.code, KeyCode::Char('o' | 'O' | 'y' | 'Y')) {
                    self.action(Action::Run(entry));
                }
            }
            Mode::Message => {
                self.mode = if self.current.is_some() {
                    Mode::Browsing
                } else {
                    Mode::Url
                };
            }
        }
        true
    }
}

fn run_script(entry: &Entry, data: &[u8]) -> Result<(), String> {
    let is_ps = entry.name.to_ascii_lowercase().ends_with(".ps1");
    let mut file = tempfile::Builder::new()
        .suffix(if is_ps { ".ps1" } else { ".sh" })
        .tempfile()
        .map_err(|e| e.to_string())?;
    file.write_all(data)
        .and_then(|_| file.flush())
        .map_err(|e| e.to_string())?;
    disable_raw_mode().map_err(|e| e.to_string())?;
    execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture).map_err(|e| e.to_string())?;
    println!("Exécution de {}\n", entry.url);
    let status = if is_ps {
        Command::new(if cfg!(windows) { "powershell" } else { "pwsh" })
            .args(["-NoProfile", "-File"])
            .arg(file.path())
            .status()
    } else {
        Command::new("bash").arg(file.path()).status()
    };
    match status {
        Ok(status) => println!("\nScript terminé : {status}"),
        Err(e) => println!("\nImpossible de démarrer le script : {e}"),
    }
    println!("Appuyez sur Entrée pour revenir au dépôt.");
    let _ = io::stdin().read_line(&mut String::new());
    enable_raw_mode().map_err(|e| e.to_string())?;
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture).map_err(|e| e.to_string())?;
    Ok(())
}

fn draw(frame: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(3),
            Constraint::Length(3),
        ])
        .split(frame.area());
    let location = app
        .current
        .as_ref()
        .map_or("Saisissez l’adresse d’un dépôt", |url| url.as_str());
    frame.render_widget(
        Paragraph::new(location).block(
            Block::default()
                .title(" MyEasyToolkit ")
                .borders(Borders::ALL),
        ),
        chunks[0],
    );
    let items: Vec<ListItem> = app
        .entries
        .iter()
        .map(|entry| {
            ListItem::new(Line::from(vec![
                Span::styled(
                    if entry.directory { "  📁 " } else { "  ·  " },
                    Style::default().fg(Color::Cyan),
                ),
                Span::raw(&entry.name),
            ]))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().title(" Dépôt ").borders(Borders::ALL))
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("›");
    frame.render_stateful_widget(list, chunks[1], &mut app.state);
    frame.render_widget(
        Paragraph::new(
            "↑/↓ naviguer  Entrée ouvrir  ← retour  o autre dépôt  r actualiser  q quitter",
        )
        .wrap(Wrap { trim: true })
        .block(Block::default().borders(Borders::ALL)),
        chunks[2],
    );
    let prompt = match &app.mode {
        Mode::Url => Some((
            " Adresse du dépôt ",
            format!("{}\n{}", app.input, app.message),
        )),
        Mode::Username(_) => Some((" Authentification : identifiant ", app.input.clone())),
        Mode::Password(_, _) => Some((
            " Authentification : mot de passe ",
            "•".repeat(app.input.chars().count()),
        )),
        Mode::Confirm(entry) => Some((
            " Confirmer l’exécution ",
            format!("{}\nExécuter ce script distant ? [o/N]", entry.url),
        )),
        Mode::Message => Some((
            " Information ",
            format!("{}\nAppuyez sur une touche.", app.message),
        )),
        Mode::Browsing => None,
    };
    if let Some((title, text)) = prompt {
        let area = frame.area();
        let width = area.width.saturating_sub(4).min(90);
        let height = area.height.saturating_sub(2).min(7);
        let popup = ratatui::layout::Rect::new(
            area.x + (area.width - width) / 2,
            area.y + (area.height - height) / 2,
            width,
            height,
        );
        frame.render_widget(Clear, popup);
        frame.render_widget(
            Paragraph::new(text).wrap(Wrap { trim: false }).block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .style(Style::default().bg(Color::Black)),
            ),
            popup,
        );
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let argument = std::env::args().nth(1);
    match argument.as_deref() {
        Some("--version" | "-V") => {
            println!("myeasytoolkit {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        Some("--help" | "-h") => {
            println!("Usage : myeasytoolkit [URL_DU_DEPOT]\nNaviguez avec le clavier ou la souris ; confirmez avant chaque exécution.");
            return Ok(());
        }
        _ => {}
    }
    let mut app = App::new().map_err(io::Error::other)?;
    if let Some(url) = argument {
        match normalize_url(&url) {
            Ok(url) => app.action(Action::OpenRoot(url)),
            Err(e) => app.error(e),
        }
    }
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let result = (|| -> io::Result<()> {
        loop {
            terminal.draw(|f| draw(f, &mut app))?;
            match event::read()? {
                Event::Key(key) if key.kind == event::KeyEventKind::Press => {
                    if !app.key(key) {
                        break;
                    }
                }
                Event::Mouse(mouse) if matches!(app.mode, Mode::Browsing) => match mouse.kind {
                    MouseEventKind::ScrollDown => app.move_selection(1),
                    MouseEventKind::ScrollUp => app.move_selection(-1),
                    MouseEventKind::Down(_)
                        if mouse.row >= 4
                            && mouse.row < terminal.size()?.height.saturating_sub(4) =>
                    {
                        let index = app.state.offset() + usize::from(mouse.row - 4);
                        if index < app.entries.len() {
                            app.state.select(Some(index));
                            app.select();
                        }
                    }
                    _ => {}
                },
                _ => {}
            }
        }
        Ok(())
    })();
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    result?;
    Ok(())
}

mod repository;

use crossterm::{
    event::{
        self, DisableBracketedPaste, DisableMouseCapture, EnableBracketedPaste, EnableMouseCapture,
        Event, KeyCode, KeyEvent, KeyModifiers, MouseEventKind,
    },
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame, Terminal,
};
use repository::{
    github_url, is_github_api, local_listing, normalize_url, parse_github_listing, parse_listing,
    Entry, FetchError, Repository,
};
use std::{
    io::{self, Write},
    process::Command,
};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};
use url::Url;

#[derive(Default)]
struct Input {
    text: String,
    cursor: usize,
}

impl Input {
    fn clear(&mut self) {
        self.text.clear();
        self.cursor = 0;
    }

    fn take(&mut self) -> String {
        self.cursor = 0;
        std::mem::take(&mut self.text)
    }

    fn insert(&mut self, text: &str) {
        // A field is always one line, including when text is pasted.
        let filtered: String = text.chars().filter(|c| !c.is_control()).collect();
        self.text.insert_str(self.cursor, &filtered);
        self.cursor += filtered.len();
    }

    fn key(&mut self, key: KeyEvent) {
        let control = key.modifiers.contains(KeyModifiers::CONTROL);
        match key.code {
            KeyCode::Left => {
                self.cursor = self.text[..self.cursor]
                    .char_indices()
                    .next_back()
                    .map_or(0, |(i, _)| i);
            }
            KeyCode::Right => {
                if let Some(c) = self.text[self.cursor..].chars().next() {
                    self.cursor += c.len_utf8();
                }
            }
            KeyCode::Home | KeyCode::Char('a') if control => self.cursor = 0,
            KeyCode::End | KeyCode::Char('e') if control => self.cursor = self.text.len(),
            KeyCode::Home => self.cursor = 0,
            KeyCode::End => self.cursor = self.text.len(),
            KeyCode::Char('u') if control => {
                self.text.drain(..self.cursor);
                self.cursor = 0;
            }
            KeyCode::Backspace if self.cursor > 0 => {
                let previous = self.text[..self.cursor]
                    .char_indices()
                    .next_back()
                    .map_or(0, |(i, _)| i);
                self.text.drain(previous..self.cursor);
                self.cursor = previous;
            }
            KeyCode::Delete if self.cursor < self.text.len() => {
                let len = self.text[self.cursor..]
                    .chars()
                    .next()
                    .expect("cursor is in bounds")
                    .len_utf8();
                self.text.drain(self.cursor..self.cursor + len);
            }
            KeyCode::Char(c) if !control && !key.modifiers.contains(KeyModifiers::ALT) => {
                self.insert(&c.to_string());
            }
            _ => {}
        }
    }

    fn click(&mut self, width: usize, column: usize, secret: bool) {
        let (visible, _) = self.visible(width, secret);
        let skipped = if secret {
            self.text
                .chars()
                .count()
                .saturating_sub(visible.chars().count())
        } else {
            self.text.len().saturating_sub(visible.len())
        };
        let start = if secret {
            self.text
                .char_indices()
                .nth(skipped)
                .map_or(self.text.len(), |(i, _)| i)
        } else {
            skipped
        };
        let mut position = 0;
        self.cursor = start;
        for c in self.text[start..].chars() {
            let cell_width = if secret {
                1
            } else {
                UnicodeWidthChar::width(c).unwrap_or(0)
            };
            if position + cell_width > column {
                break;
            }
            position += cell_width;
            self.cursor += c.len_utf8();
        }
    }

    // Keep the caret visible without splitting a Unicode character or exposing passwords.
    fn visible(&self, width: usize, secret: bool) -> (String, usize) {
        if width == 0 {
            return (String::new(), 0);
        }
        let before = &self.text[..self.cursor];
        let display = if secret {
            "•".repeat(self.text.chars().count())
        } else {
            self.text.clone()
        };
        let caret = if secret {
            before.chars().count()
        } else {
            UnicodeWidthStr::width(before)
        };
        let mut skipped = 0;
        let mut start = 0;
        for (index, c) in display.char_indices() {
            if caret.saturating_sub(skipped) < width {
                break;
            }
            skipped += UnicodeWidthChar::width(c).unwrap_or(0);
            start = index + c.len_utf8();
        }
        (
            display[start..].to_owned(),
            caret.saturating_sub(skipped).min(width - 1),
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Source {
    Local,
    Http,
    Github,
}

fn source_for(url: &Url) -> Source {
    if url.scheme() == "file" {
        Source::Local
    } else if is_github_api(url) {
        Source::Github
    } else {
        Source::Http
    }
}

fn location_label(url: &Url) -> String {
    if url.scheme() == "file" {
        return url
            .to_file_path()
            .map_or_else(|_| url.to_string(), |p| p.display().to_string());
    }
    if is_github_api(url) {
        let parts: Vec<_> = url
            .path()
            .trim_start_matches("/repos/")
            .splitn(3, '/')
            .collect();
        if parts.len() == 3 {
            let tail = parts[2].strip_prefix("contents/").unwrap_or("");
            return format!("https://github.com/{}/{}/{}", parts[0], parts[1], tail);
        }
    }
    url.to_string()
}

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
    input: Input,
    input_source: Source,
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
            input: Input::default(),
            input_source: Source::Http,
            message: String::new(),
        })
    }
    fn action(&mut self, action: Action) {
        let url = match &action {
            Action::Open(url) | Action::OpenRoot(url) => url,
            Action::Run(entry) => &entry.url,
        };
        let is_new_root = matches!(action, Action::OpenRoot(_));
        let result = if url.scheme() == "file" {
            match &action {
                Action::Open(_) | Action::OpenRoot(_) => local_listing(url)
                    .map(|entries| (Vec::new(), Some(entries)))
                    .map_err(FetchError::Message),
                Action::Run(_) => Ok((Vec::new(), None)),
            }
        } else if is_github_api(url) && matches!(action, Action::Run(_)) {
            self.repo.fetch_github_script(url).map(|data| (data, None))
        } else {
            self.repo.fetch(url).map(|data| (data, None))
        };
        match result {
            Ok((data, local_entries)) => match action {
                Action::Open(url) | Action::OpenRoot(url) => {
                    self.entries = if let Some(entries) = local_entries {
                        entries
                    } else if is_github_api(&url) {
                        match parse_github_listing(&url, &data) {
                            Ok(entries) => entries,
                            Err(error) => {
                                self.error(error);
                                return;
                            }
                        }
                    } else {
                        parse_listing(&url, &String::from_utf8_lossy(&data))
                    };
                    self.current = Some(url.clone());
                    if is_new_root || self.root.is_none() {
                        self.root = Some(url);
                    }
                    self.state.select((!self.entries.is_empty()).then_some(0));
                    self.input.clear();
                    self.message.clear();
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
            Err(FetchError::Message(e)) if is_new_root && url.scheme() != "file" => {
                if self.input.text.is_empty() {
                    self.input.insert(&location_label(url));
                }
                self.message = e;
                self.mode = Mode::Url;
            }
            Err(FetchError::Message(e)) => self.error(e),
        }
    }
    fn select_source(&mut self, source: Source) {
        self.message.clear();
        self.input.clear();
        self.input_source = source;
        if source == Source::Local {
            match std::env::current_dir()
                .ok()
                .and_then(|p| Url::from_directory_path(p).ok())
            {
                Some(url) => {
                    let filesystem_root = url.to_file_path().ok().and_then(|path| {
                        path.ancestors()
                            .last()
                            .and_then(|root| Url::from_directory_path(root).ok())
                    });
                    self.action(Action::OpenRoot(url));
                    if matches!(self.mode, Mode::Browsing) {
                        self.root = filesystem_root;
                    }
                }
                None => self.error("Impossible de lire le dossier courant.".into()),
            }
        } else {
            self.input.insert(if source == Source::Github {
                "https://github.com/"
            } else {
                "https://"
            });
            self.mode = Mode::Url;
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
                KeyCode::Char('o' | '2') => self.select_source(Source::Http),
                KeyCode::Char('1') => self.select_source(Source::Local),
                KeyCode::Char('3') => self.select_source(Source::Github),
                _ => {}
            },
            Mode::Url => match key.code {
                KeyCode::Enter => match if self.input_source == Source::Github {
                    github_url(&self.input.text)
                } else {
                    normalize_url(&self.input.text)
                } {
                    Ok(url) => {
                        self.message.clear();
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
                _ => {
                    self.input.key(key);
                    self.message.clear();
                    self.mode = Mode::Url;
                }
            },
            Mode::Username(action) => match key.code {
                KeyCode::Enter => {
                    let username = self.input.take();
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
                _ => {
                    self.input.key(key);
                    self.mode = Mode::Username(action);
                }
            },
            Mode::Password(action, username) => match key.code {
                KeyCode::Enter => {
                    let password = self.input.take();
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
                _ => {
                    self.input.key(key);
                    self.mode = Mode::Password(action, username);
                }
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
    let local_path = entry.url.to_file_path().ok();
    let mut temporary = if local_path.is_none() {
        let mut file = tempfile::Builder::new()
            .suffix(if is_ps { ".ps1" } else { ".sh" })
            .tempfile()
            .map_err(|e| e.to_string())?;
        file.write_all(data)
            .and_then(|_| file.flush())
            .map_err(|e| e.to_string())?;
        Some(file)
    } else {
        None
    };
    let script_path = match (&local_path, &mut temporary) {
        (Some(path), _) => path.as_path(),
        (_, Some(file)) => file.path(),
        _ => return Err("Chemin du script indisponible.".into()),
    };
    disable_raw_mode().map_err(|e| e.to_string())?;
    execute!(
        io::stdout(),
        LeaveAlternateScreen,
        DisableMouseCapture,
        DisableBracketedPaste
    )
    .map_err(|e| e.to_string())?;
    println!("Exécution de {}\n", location_label(&entry.url));
    let status = if is_ps {
        Command::new(if cfg!(windows) { "powershell" } else { "pwsh" })
            .args(["-NoProfile", "-File"])
            .arg(script_path)
            .status()
    } else {
        Command::new("bash").arg(script_path).status()
    };
    match status {
        Ok(status) => println!("\nScript terminé : {status}"),
        Err(e) => println!("\nImpossible de démarrer le script : {e}"),
    }
    println!("Appuyez sur Entrée pour revenir au dépôt.");
    let _ = io::stdin().read_line(&mut String::new());
    enable_raw_mode().map_err(|e| e.to_string())?;
    execute!(
        io::stdout(),
        EnterAlternateScreen,
        EnableMouseCapture,
        EnableBracketedPaste
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

struct UiAreas {
    header: Rect,
    sources: Rect,
    location: Rect,
    list: Rect,
    footer: Rect,
}
impl UiAreas {
    fn new(area: Rect) -> Self {
        let parts = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(2),
                Constraint::Length(2),
                Constraint::Length(3),
                Constraint::Min(3),
                Constraint::Length(2),
            ])
            .split(area);
        Self {
            header: parts[0],
            sources: parts[1],
            location: parts[2],
            list: parts[3],
            footer: parts[4],
        }
    }
}
fn popup_area(area: Rect) -> Rect {
    let width = area.width.saturating_sub(2).min(76);
    let height = area.height.saturating_sub(2).min(8);
    Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    )
}
fn contains(area: Rect, x: u16, y: u16) -> bool {
    x >= area.x && x < area.right() && y >= area.y && y < area.bottom()
}
fn draw(frame: &mut Frame, app: &mut App) {
    let areas = UiAreas::new(frame.area());
    let accent = Style::default()
        .fg(Color::Cyan)
        .add_modifier(Modifier::BOLD);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(" MyEasyToolkit ", accent),
            Span::styled("  Navigateur de scripts", Style::default().fg(Color::Gray)),
        ])),
        areas.header,
    );
    let active = if matches!(app.mode, Mode::Url) {
        app.input_source
    } else {
        app.current.as_ref().map_or(Source::Local, source_for)
    };
    let source_style = |source| {
        if active == source {
            Style::default()
                .fg(Color::Black)
                .bg(Color::Cyan)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::White)
        }
    };
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::raw(" "),
            Span::styled("[1 Local]", source_style(Source::Local)),
            Span::raw("  "),
            Span::styled("[2 HTTP]", source_style(Source::Http)),
            Span::raw("  "),
            Span::styled("[3 GitHub]", source_style(Source::Github)),
            Span::styled("    Source", Style::default().fg(Color::Gray)),
        ])),
        areas.sources,
    );
    let editing = matches!(app.mode, Mode::Url);
    let title = if editing {
        if app.input_source == Source::Github {
            " Dépôt GitHub public · Entrée pour ouvrir "
        } else {
            " Adresse HTTP · Entrée pour ouvrir "
        }
    } else {
        " Emplacement "
    };
    frame.render_widget(
        Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(if editing {
                accent
            } else {
                Style::default().fg(Color::DarkGray)
            }),
        areas.location,
    );
    if areas.location.width > 2 && areas.location.height > 2 {
        let field = Rect::new(
            areas.location.x + 1,
            areas.location.y + 1,
            areas.location.width - 2,
            1,
        );
        if editing {
            let (text, caret) = app.input.visible(field.width as usize, false);
            frame.render_widget(Paragraph::new(text), field);
            frame.set_cursor_position((field.x + caret as u16, field.y));
        } else {
            let text = app
                .current
                .as_ref()
                .map_or_else(|| "Choisissez une source".to_string(), location_label);
            frame.render_widget(Paragraph::new(text), field);
        }
    }
    let items: Vec<ListItem> = app
        .entries
        .iter()
        .map(|entry| {
            let kind = if entry.directory { "  [D] " } else { "  [F] " };
            ListItem::new(Line::from(vec![
                Span::styled(kind, Style::default().fg(Color::Cyan)),
                Span::raw(&entry.name),
            ]))
        })
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .title(" Fichiers · [D] dossier  [F] fichier ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Gray)),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("›");
    frame.render_stateful_widget(list, areas.list, &mut app.state);
    if app.entries.is_empty()
        && app.current.is_some()
        && areas.list.width > 2
        && areas.list.height > 2
    {
        frame.render_widget(
            Paragraph::new("Aucun fichier ni dossier trouvé.")
                .style(Style::default().fg(Color::Gray)),
            Rect::new(areas.list.x + 1, areas.list.y + 1, areas.list.width - 2, 1),
        );
    }
    let footer = if editing {
        if app.message.is_empty() {
            " Entrée ouvrir  ·  Échap annuler  ·  ←/→ déplacer le curseur"
        } else {
            app.message.as_str()
        }
    } else {
        " ↑/↓ naviguer  ·  Entrée ouvrir  ·  ← retour  ·  r actualiser  ·  q quitter"
    };
    frame.render_widget(
        Paragraph::new(footer)
            .style(if editing && !app.message.is_empty() {
                Style::default().fg(Color::Red)
            } else {
                Style::default().fg(Color::Gray)
            })
            .wrap(Wrap { trim: true }),
        areas.footer,
    );

    let input_prompt = match &app.mode {
        Mode::Username(_) => Some((" Connexion au dépôt ", "Identifiant", false)),
        Mode::Password(_, _) => Some((" Connexion au dépôt ", "Mot de passe", true)),
        _ => None,
    };
    if let Some((title, label, secret)) = input_prompt {
        let popup = popup_area(frame.area());
        frame.render_widget(Clear, popup);
        frame.render_widget(
            Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_style(accent),
            popup,
        );
        let inner_width = popup.width.saturating_sub(4);
        if popup.height >= 4 && inner_width > 0 {
            let x = popup.x + 2;
            let y = popup.y + 1;
            frame.render_widget(
                Paragraph::new(label).style(Style::default().add_modifier(Modifier::BOLD)),
                Rect::new(x, y, inner_width, 1),
            );
            let (text, caret) = app.input.visible(inner_width as usize, secret);
            frame.render_widget(Paragraph::new(text), Rect::new(x, y + 1, inner_width, 1));
            frame.set_cursor_position((x + caret as u16, y + 1));
            if popup.height >= 6 {
                frame.render_widget(
                    Paragraph::new("[Continuer]   Échap : annuler")
                        .style(Style::default().fg(Color::Gray)),
                    Rect::new(x, y + 3, inner_width, 1),
                );
            }
        }
    } else {
        let prompt = match &app.mode {
            Mode::Confirm(entry) => Some((
                " Confirmer l’exécution ",
                format!("{}\n\nExécuter ce script ?", location_label(&entry.url)),
            )),
            Mode::Message => Some((
                " Information ",
                format!("{}\n\nAppuyez sur une touche.", app.message),
            )),
            _ => None,
        };
        if let Some((title, text)) = prompt {
            let popup = popup_area(frame.area());
            frame.render_widget(Clear, popup);
            frame.render_widget(
                Paragraph::new(text).wrap(Wrap { trim: false }).block(
                    Block::default()
                        .title(title)
                        .borders(Borders::ALL)
                        .border_style(accent),
                ),
                popup,
            );
            if matches!(app.mode, Mode::Confirm(_)) && popup.width > 4 && popup.height >= 5 {
                frame.render_widget(
                    Paragraph::new("[Exécuter]   [Annuler]   o / Échap")
                        .style(Style::default().fg(Color::Cyan)),
                    Rect::new(popup.x + 2, popup.bottom() - 2, popup.width - 4, 1),
                );
            }
        }
    }
}

fn mouse(app: &mut App, mouse: crossterm::event::MouseEvent, area: Rect) {
    let areas = UiAreas::new(area);
    match mouse.kind {
        MouseEventKind::ScrollDown if matches!(app.mode, Mode::Browsing) => app.move_selection(1),
        MouseEventKind::ScrollUp if matches!(app.mode, Mode::Browsing) => app.move_selection(-1),
        MouseEventKind::Down(crossterm::event::MouseButton::Left) => {
            let x = mouse.column;
            let y = mouse.row;
            if matches!(app.mode, Mode::Browsing | Mode::Url)
                && y == areas.sources.y
                && x > areas.sources.x
            {
                let col = x - areas.sources.x;
                if (1..=9).contains(&col) {
                    app.select_source(Source::Local);
                } else if (12..=19).contains(&col) {
                    app.select_source(Source::Http);
                } else if (22..=31).contains(&col) {
                    app.select_source(Source::Github);
                }
            } else if matches!(app.mode, Mode::Url)
                && areas.location.width > 2
                && y == areas.location.y + 1
                && x > areas.location.x
                && x < areas.location.right() - 1
            {
                app.input.click(
                    (areas.location.width - 2) as usize,
                    (x - areas.location.x - 1) as usize,
                    false,
                );
            } else if matches!(app.mode, Mode::Browsing) && contains(areas.location, x, y) {
                let source = app.current.as_ref().map_or(Source::Http, source_for);
                if source != Source::Local {
                    let current = app.current.as_ref().map(location_label).unwrap_or_default();
                    app.select_source(source);
                    if source == Source::Http {
                        app.input.clear();
                        app.input.insert(&current);
                    }
                }
            } else if matches!(app.mode, Mode::Browsing)
                && x > areas.list.x
                && x < areas.list.right().saturating_sub(1)
                && y > areas.list.y
                && y < areas.list.bottom().saturating_sub(1)
            {
                let index = app.state.offset() + usize::from(y - areas.list.y - 1);
                if index < app.entries.len() {
                    app.state.select(Some(index));
                    app.select();
                }
            } else if matches!(app.mode, Mode::Username(_) | Mode::Password(_, _)) {
                let popup = popup_area(area);
                if popup.width > 4
                    && popup.height >= 4
                    && y == popup.y + 2
                    && x >= popup.x + 2
                    && x < popup.right() - 2
                {
                    app.input.click(
                        (popup.width - 4) as usize,
                        (x - popup.x - 2) as usize,
                        matches!(app.mode, Mode::Password(_, _)),
                    );
                } else if popup.width > 4
                    && popup.height >= 6
                    && y == popup.y + 4
                    && x >= popup.x + 2
                    && x < (popup.x + 13).min(popup.right())
                {
                    app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
                }
            } else if matches!(app.mode, Mode::Confirm(_)) {
                let popup = popup_area(area);
                if popup.width > 4 && popup.height >= 5 && y == popup.bottom() - 2 {
                    if x >= popup.x + 2 && x < popup.x + 12 {
                        app.key(KeyEvent::new(KeyCode::Char('o'), KeyModifiers::NONE));
                    } else if x >= popup.x + 15 && x < popup.x + 24 {
                        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
                    }
                }
            } else if matches!(app.mode, Mode::Message) {
                app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
            }
        }
        _ => {}
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
        let github = url.starts_with("https://github.com/");
        app.input_source = if github { Source::Github } else { Source::Http };
        app.input.insert(&url);
        match if github {
            github_url(&url)
        } else {
            normalize_url(&url)
        } {
            Ok(url) => app.action(Action::OpenRoot(url)),
            Err(e) => {
                app.message = e;
                app.mode = Mode::Url;
            }
        }
    } else {
        app.select_source(Source::Local);
    }
    enable_raw_mode()?;
    execute!(
        io::stdout(),
        EnterAlternateScreen,
        EnableMouseCapture,
        EnableBracketedPaste
    )?;
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
                Event::Paste(text)
                    if matches!(
                        app.mode,
                        Mode::Url | Mode::Username(_) | Mode::Password(_, _)
                    ) =>
                {
                    if matches!(app.mode, Mode::Url)
                        && (app.input.text == "https://" || app.input.text == "https://github.com/")
                        && text.trim_start().starts_with("http")
                    {
                        app.input.clear();
                    }
                    app.input.insert(&text);
                    app.message.clear();
                }
                Event::Mouse(event) => mouse(&mut app, event, terminal.get_frame().area()),
                _ => {}
            }
        }
        Ok(())
    })();
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture,
        DisableBracketedPaste
    )?;
    terminal.show_cursor()?;
    result?;
    Ok(())
}

#[cfg(test)]
mod input_tests {
    use super::*;
    use ratatui::backend::TestBackend;

    fn press(input: &mut Input, key: KeyCode) {
        input.key(KeyEvent::new(key, KeyModifiers::NONE));
    }

    #[test]
    fn edits_and_pastes_at_the_cursor_on_unicode_boundaries() {
        let mut input = Input::default();
        input.insert("éxample.ovh");
        for _ in 0..10 {
            press(&mut input, KeyCode::Left);
        }
        press(&mut input, KeyCode::Backspace);
        input.insert("e");
        assert_eq!(input.text, "example.ovh");
        press(&mut input, KeyCode::Delete);
        input.insert("X\nY");
        assert_eq!(input.text, "eXYample.ovh");
        press(&mut input, KeyCode::Home);
        press(&mut input, KeyCode::Backspace);
        press(&mut input, KeyCode::End);
        press(&mut input, KeyCode::Delete);
        assert_eq!(input.text, "eXYample.ovh");
    }

    #[test]
    fn long_fields_scroll_and_passwords_remain_masked() {
        let mut input = Input::default();
        input.insert("abc界é");
        let (visible, caret) = input.visible(4, false);
        assert_eq!(visible, "界é");
        assert_eq!(caret, 3);
        let (masked, caret) = input.visible(4, true);
        assert_eq!(masked, "•••");
        assert_eq!(caret, 3);
        press(&mut input, KeyCode::Home);
        assert_eq!(input.visible(4, false).1, 0);
    }

    #[test]
    fn invalid_address_remains_editable_and_error_disappears_after_edit() {
        let mut app = App::new().unwrap();
        app.input.insert("https://user:password@example.com/");
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert!(matches!(app.mode, Mode::Url));
        assert!(!app.message.is_empty());
        assert!(app.input.text.contains("user:password"));
        app.key(KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE));
        assert!(app.message.is_empty());
    }

    #[test]
    fn mouse_selects_sources_edits_address_and_opens_local_folders() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let click = |x, y| MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: x,
            row: y,
            modifiers: KeyModifiers::NONE,
        };
        let screen = Rect::new(0, 0, 80, 24);
        let areas = UiAreas::new(screen);
        let mut app = App::new().unwrap();
        mouse(&mut app, click(13, areas.sources.y), screen);
        assert!(matches!(app.mode, Mode::Url));
        assert_eq!(app.input.text, "https://");
        mouse(&mut app, click(5, areas.location.y + 1), screen);
        assert_eq!(app.input.cursor, 4);
        app.key(KeyEvent::new(KeyCode::Delete, KeyModifiers::NONE));
        assert_eq!(app.input.text, "http://");
        mouse(&mut app, click(23, areas.sources.y), screen);
        assert_eq!(app.input_source, Source::Github);
        assert_eq!(app.input.text, "https://github.com/");

        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("child")).unwrap();
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        mouse(&mut app, click(3, areas.list.y + 1), screen);
        assert_eq!(
            app.current.unwrap().to_file_path().unwrap(),
            dir.path().join("child")
        );
    }

    #[test]
    fn selecting_a_script_requires_confirmation_and_mouse_can_cancel() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.select();
        assert!(matches!(app.mode, Mode::Confirm(_)));
        let screen = Rect::new(0, 0, 80, 24);
        let popup = popup_area(screen);
        mouse(
            &mut app,
            MouseEvent {
                kind: MouseEventKind::Down(MouseButton::Left),
                column: popup.x + 15,
                row: popup.bottom() - 2,
                modifiers: KeyModifiers::NONE,
            },
            screen,
        );
        assert!(matches!(app.mode, Mode::Browsing));
    }

    #[test]
    fn prompts_render_on_normal_and_small_terminals_without_revealing_password() {
        for (width, height) in [(80, 24), (32, 12), (8, 4)] {
            let mut app = App::new().unwrap();
            app.mode = Mode::Password(
                Action::OpenRoot(Url::parse("https://example.com/").unwrap()),
                "alice".into(),
            );
            app.input.insert("secret");
            let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
            terminal.draw(|frame| draw(frame, &mut app)).unwrap();
            let content = format!("{:?}", terminal.backend().buffer());
            assert!(!content.contains("secret"));
        }
    }
}

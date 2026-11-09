mod console;
mod description;
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
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame, Terminal,
};
use repository::{
    github_url, is_github_api, local_listing, normalize_url, parse_github_listing, parse_listing,
    Entry, FetchError, Repository,
};
use std::{
    collections::HashMap,
    io,
    path::{Path, PathBuf},
    process::Command,
    sync::Arc,
    time::Duration,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Sources,
    Filter,
    Contents,
    Controls,
}

const SOURCES: [Source; 3] = [Source::Local, Source::Http, Source::Github];

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
    RunBatch(Entry),
}
enum Mode {
    Url,
    Browsing,
    Username(Action),
    Password(Action, String),
    Confirm(Entry),
    ConfirmBatch,
    Message,
}
struct BatchRun {
    entries: Vec<Entry>,
    next: usize,
    failures: Vec<String>,
    stop_on_error: bool,
}
type ScriptRunner<'a> = dyn FnMut(&Entry, &[u8], bool, bool) -> Result<(), String> + 'a;

fn is_script(entry: &Entry) -> bool {
    !entry.directory
        && (description::leaf(entry)
            .to_ascii_lowercase()
            .ends_with(".sh")
            || description::leaf(entry)
                .to_ascii_lowercase()
                .ends_with(".ps1"))
}

#[derive(Clone, Debug, Default)]
struct Interpreters {
    bash: Option<PathBuf>,
    powershell: Option<PathBuf>,
}
impl Interpreters {
    fn detect() -> Self {
        let paths: Vec<PathBuf> = std::env::var_os("PATH")
            .map(|v| std::env::split_paths(&v).collect())
            .unwrap_or_default();
        let bash = if cfg!(windows) {
            &["bash.exe"][..]
        } else {
            &["bash"][..]
        };
        let powershell = if cfg!(windows) {
            &["pwsh.exe", "powershell.exe"][..]
        } else {
            &["pwsh", "powershell"][..]
        };
        Self {
            bash: find_program(&paths, bash),
            powershell: find_program(&paths, powershell),
        }
    }
    fn supports(&self, entry: &Entry) -> bool {
        let name = description::leaf(entry).to_ascii_lowercase();
        !entry.directory
            && ((name.ends_with(".sh") && self.bash.is_some())
                || (name.ends_with(".ps1") && self.powershell.is_some()))
    }
}
fn find_program(paths: &[PathBuf], names: &[&str]) -> Option<PathBuf> {
    for name in names {
        for path in paths {
            let candidate = path.join(name);
            if let Ok(meta) = candidate.metadata() {
                #[cfg(unix)]
                let executable = {
                    use std::os::unix::fs::PermissionsExt;
                    meta.permissions().mode() & 0o111 != 0
                };
                #[cfg(not(unix))]
                let executable = true;
                if meta.is_file() && executable {
                    return Some(candidate);
                }
            }
        }
    }
    None
}

struct App {
    repo: Repository,
    root: Option<Url>,
    current: Option<Url>,
    entries: Vec<Entry>,
    all_entries: Vec<Entry>,
    interpreters: Interpreters,
    show_all: bool,
    descriptions: HashMap<Url, Result<String, String>>,
    loader: description::Loader,
    description_generation: u64,
    description_focus: Option<Url>,
    description_scroll: usize,
    screen_needs_redraw: bool,
    state: ListState,
    mode: Mode,
    input: Input,
    input_source: Source,
    focus: Focus,
    source_cursor: Source,
    control_focus: usize,
    dialog_focus: usize,
    auth_focus: usize,
    icons: bool,
    message: String,
    selected_scripts: Vec<Entry>,
    stop_on_error: bool,
    batch: Option<BatchRun>,
    batch_scroll: usize,
}
impl App {
    fn new() -> Result<Self, String> {
        Ok(Self {
            repo: Repository::new()?,
            root: None,
            current: None,
            entries: vec![],
            all_entries: vec![],
            interpreters: Interpreters::detect(),
            show_all: false,
            descriptions: HashMap::new(),
            loader: description::Loader::new(),
            description_generation: 0,
            description_focus: None,
            description_scroll: 0,
            screen_needs_redraw: false,
            state: ListState::default(),
            mode: Mode::Url,
            input: Input::default(),
            input_source: Source::Http,
            focus: Focus::Contents,
            source_cursor: Source::Local,
            control_focus: 0,
            dialog_focus: 0,
            auth_focus: 0,
            icons: std::env::var_os("MYEASYTOOLKIT_ASCII").is_none()
                && std::env::var("TERM").as_deref() != Ok("dumb"),
            message: String::new(),
            selected_scripts: Vec::new(),
            stop_on_error: true,
            batch: None,
            batch_scroll: 0,
        })
    }
    fn action(&mut self, action: Action) {
        self.action_with_runner(action, &mut run_script);
    }
    fn action_with_runner(&mut self, action: Action, runner: &mut ScriptRunner<'_>) {
        let url = match &action {
            Action::Open(url) | Action::OpenRoot(url) => url,
            Action::Run(entry) | Action::RunBatch(entry) => &entry.url,
        };
        let is_new_root = matches!(action, Action::OpenRoot(_));
        let result = if url.scheme() == "file" {
            match &action {
                Action::Open(_) | Action::OpenRoot(_) => local_listing(url)
                    .map(|entries| (Vec::new(), Some(entries)))
                    .map_err(FetchError::Message),
                Action::Run(_) | Action::RunBatch(_) => Ok((Vec::new(), None)),
            }
        } else if is_github_api(url) && matches!(action, Action::Run(_) | Action::RunBatch(_)) {
            self.repo.fetch_github_script(url).map(|data| (data, None))
        } else {
            self.repo.fetch(url).map(|data| (data, None))
        };
        match result {
            Ok((data, local_entries)) => match action {
                Action::Open(url) | Action::OpenRoot(url) => {
                    self.all_entries = if let Some(entries) = local_entries {
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
                    self.source_cursor = source_for(&url);
                    self.focus = Focus::Contents;
                    if is_new_root || self.root.is_none() {
                        self.root = Some(url);
                    }
                    self.state.select(None);
                    self.apply_filter();
                    self.load_descriptions();
                    self.input.clear();
                    self.message.clear();
                    self.mode = Mode::Browsing;
                }
                Action::Run(entry) => {
                    self.mode = Mode::Browsing;
                    self.screen_needs_redraw = true;
                    if let Err(e) = runner(&entry, &data, true, true) {
                        self.error(e);
                    }
                }
                Action::RunBatch(entry) => {
                    self.screen_needs_redraw = true;
                    let wait = self
                        .batch
                        .as_ref()
                        .is_some_and(|batch| batch.next + 1 == batch.entries.len());
                    let stop_on_error =
                        self.batch.as_ref().is_some_and(|batch| batch.stop_on_error);
                    let result = runner(&entry, &data, wait, stop_on_error);
                    self.finish_batch_step(&entry, result);
                }
            },
            Err(FetchError::Unauthorized) => {
                self.input.clear();
                self.auth_focus = 0;
                self.mode = Mode::Username(action);
            }
            Err(FetchError::Message(e)) if is_new_root && url.scheme() != "file" => {
                self.auth_focus = 0;
                if self.input.text.is_empty() {
                    self.input.insert(&location_label(url));
                }
                self.message = e;
                self.mode = Mode::Url;
            }
            Err(FetchError::Message(e)) => match action {
                Action::RunBatch(entry) => self.finish_batch_step(&entry, Err(e)),
                _ => self.error(e),
            },
        }
    }
    fn apply_filter(&mut self) {
        let selected = self
            .state
            .selected()
            .and_then(|i| self.entries.get(i))
            .map(|entry| entry.url.clone());
        self.entries = self
            .all_entries
            .iter()
            .filter(|entry| {
                if description::protected(entry) {
                    return false;
                }
                if self.show_all {
                    return true;
                }
                let hidden =
                    entry.name.starts_with('.') || description::leaf(entry).starts_with('.');
                !hidden && (entry.directory || self.interpreters.supports(entry))
            })
            .cloned()
            .collect();
        self.state.select(
            selected
                .and_then(|url| self.entries.iter().position(|entry| entry.url == url))
                .or_else(|| (!self.entries.is_empty()).then_some(0)),
        );
        self.description_focus = None;
        self.description_scroll = 0;
    }
    fn load_descriptions(&mut self) {
        self.description_generation = self.description_generation.wrapping_add(1);
        self.descriptions.clear();
        self.description_focus = None;
        self.description_scroll = 0;
        let mut urls = Vec::new();
        for entry in &self.entries {
            if is_script(entry) && !description::protected(entry) {
                if let Some(sidecar) = description::sidecar(entry, &self.all_entries) {
                    if !urls.contains(&sidecar.url) {
                        urls.push(sidecar.url.clone());
                    }
                }
            }
        }
        let _ = self.loader.requests.send(description::Request::Replace(
            self.description_generation,
            Arc::new(self.repo.clone()),
            urls,
        ));
    }
    fn update_descriptions(&mut self) {
        while let Ok((generation, url, result)) = self.loader.results.try_recv() {
            if generation == self.description_generation {
                self.descriptions.insert(url, result);
            }
        }
        let focus = self
            .state
            .selected()
            .and_then(|i| self.entries.get(i))
            .map(|entry| entry.url.clone());
        if focus != self.description_focus {
            self.description_focus = focus;
            self.description_scroll = 0;
            if let Some(entry) = self.state.selected().and_then(|i| self.entries.get(i)) {
                if let Some(sidecar) = description::sidecar(entry, &self.all_entries) {
                    let _ = self.loader.requests.send(description::Request::Prioritize(
                        self.description_generation,
                        sidecar.url.clone(),
                    ));
                }
            }
        }
    }
    fn description(&self, entry: &Entry) -> Option<&Result<String, String>> {
        let sidecar = description::sidecar(entry, &self.all_entries)?;
        self.descriptions.get(&sidecar.url)
    }
    fn description_text(&self) -> String {
        let Some(entry) = self.state.selected().and_then(|i| self.entries.get(i)) else {
            return "Sélectionnez un script pour afficher sa description.".into();
        };
        if !is_script(entry) {
            return "Sélectionnez un script pour afficher sa description.".into();
        }
        if description::sidecar(entry, &self.all_entries).is_none() {
            return "Aucune description associée à ce script.".into();
        }
        match self.description(entry) {
            Some(Ok(text)) if text.is_empty() => "La description est vide.".into(),
            Some(Ok(text)) => text.clone(),
            Some(Err(error)) => error.clone(),
            None => "Chargement de la description…".into(),
        }
    }
    fn toggle_script(&mut self) {
        let Some(entry) = self.state.selected().and_then(|i| self.entries.get(i)) else {
            return;
        };
        if !is_script(entry) {
            return;
        }
        if let Some(index) = self
            .selected_scripts
            .iter()
            .position(|item| item.url == entry.url)
        {
            self.selected_scripts.remove(index);
        } else {
            self.selected_scripts.push(entry.clone());
        }
    }
    fn confirm_batch(&mut self) {
        if !self.selected_scripts.is_empty() {
            self.batch_scroll = 0;
            self.dialog_focus = 0;
            self.mode = Mode::ConfirmBatch;
        } else {
            self.error("Sélectionnez au moins un script avec sa case ou la barre d’espace.".into());
        }
    }
    fn start_batch(&mut self) {
        if !self.selected_scripts.is_empty() {
            self.batch = Some(BatchRun {
                entries: self.selected_scripts.clone(),
                next: 0,
                failures: Vec::new(),
                stop_on_error: self.stop_on_error,
            });
            self.mode = Mode::Browsing;
        }
    }
    fn advance_batch(&mut self) {
        self.advance_batch_with(&mut run_script);
    }
    fn advance_batch_with(&mut self, runner: &mut ScriptRunner<'_>) {
        if matches!(self.mode, Mode::Browsing) {
            if let Some(entry) = self
                .batch
                .as_ref()
                .and_then(|batch| batch.entries.get(batch.next))
                .cloned()
            {
                self.action_with_runner(Action::RunBatch(entry), runner);
            }
        }
    }
    fn finish_batch_step(&mut self, entry: &Entry, result: Result<(), String>) {
        let Some(batch) = self.batch.as_mut() else {
            return;
        };
        let failed = result.is_err();
        if let Err(error) = result {
            batch
                .failures
                .push(format!("{} : {error}", location_label(&entry.url)));
        }
        batch.next += 1;
        if (failed && batch.stop_on_error) || batch.next == batch.entries.len() {
            let batch = self.batch.take().expect("batch exists");
            let skipped = batch.entries.len() - batch.next;
            let mut summary = format!(
                "{} script(s) traité(s) sur {}. {} échec(s).",
                batch.next,
                batch.entries.len(),
                batch.failures.len()
            );
            if skipped > 0 {
                summary.push_str(&format!(" {skipped} script(s) non lancé(s)."));
            }
            if let Some(error) = batch.failures.last() {
                summary.push_str(&format!("\nDernière erreur : {error}"));
            }
            self.error(summary);
        } else {
            self.mode = Mode::Browsing;
        }
    }
    fn cancel_auth(&mut self) {
        self.input.clear();
        if self.batch.take().is_some() {
            self.error(
                "Exécution interrompue : authentification annulée. La sélection est conservée."
                    .into(),
            );
        } else {
            self.mode = if self.current.is_some() {
                Mode::Browsing
            } else {
                Mode::Url
            };
        }
    }
    fn select_source(&mut self, source: Source) {
        self.auth_focus = 0;
        self.message.clear();
        self.input.clear();
        self.input_source = source;
        self.source_cursor = source;
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
    fn toggle_filter(&mut self) {
        self.show_all = !self.show_all;
        self.apply_filter();
        self.load_descriptions();
    }
    fn edit_location(&mut self) {
        let source = self.current.as_ref().map_or(Source::Http, source_for);
        if source == Source::Local {
            self.select_source(Source::Http);
        } else {
            let current = self
                .current
                .as_ref()
                .map(location_label)
                .unwrap_or_default();
            self.select_source(source);
            self.input.clear();
            self.input.insert(&current);
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
            } else if is_script(&entry) {
                self.dialog_focus = 0;
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
    fn active_source(&self) -> Source {
        self.current.as_ref().map_or(Source::Local, source_for)
    }
    fn focus_sources(&mut self) {
        self.source_cursor = self.active_source();
        self.focus = Focus::Sources;
    }
    fn focus_contents(&mut self) {
        self.source_cursor = self.active_source();
        self.focus = Focus::Contents;
    }
    fn move_source(&mut self, delta: isize) {
        let index = SOURCES
            .iter()
            .position(|source| *source == self.source_cursor)
            .unwrap_or(0);
        let next = index.saturating_add_signed(delta).min(SOURCES.len() - 1);
        self.source_cursor = SOURCES[next];
    }
    fn choose_source(&mut self) {
        if self.current.is_some() && self.source_cursor == self.active_source() {
            self.focus_contents();
        } else {
            self.select_source(self.source_cursor);
        }
    }
    fn move_selection(&mut self, delta: isize) {
        if !self.entries.is_empty() {
            let old = self.state.selected().unwrap_or(0);
            let next = old.saturating_add_signed(delta).min(self.entries.len() - 1);
            self.state.select(Some(next));
        }
    }
    // Authentication inputs keep normal caret navigation while Tab moves to buttons.
    fn auth_key(&mut self, key: KeyEvent) -> Option<bool> {
        match key.code {
            KeyCode::Esc => return Some(false),
            KeyCode::Tab => self.auth_focus = (self.auth_focus + 1) % 3,
            KeyCode::BackTab => self.auth_focus = (self.auth_focus + 2) % 3,
            KeyCode::Down if self.auth_focus == 0 => self.auth_focus = 1,
            KeyCode::Up if self.auth_focus != 0 => self.auth_focus = 0,
            KeyCode::Left | KeyCode::Right if self.auth_focus != 0 => {
                self.auth_focus = 3 - self.auth_focus
            }
            KeyCode::Enter => return Some(self.auth_focus != 2),
            KeyCode::Char(' ') if self.auth_focus != 0 => return Some(self.auth_focus != 2),
            _ if self.auth_focus == 0 => self.input.key(key),
            _ => {}
        }
        None
    }
    fn key(&mut self, key: KeyEvent) -> bool {
        let key = if key.code == KeyCode::Tab && key.modifiers.contains(KeyModifiers::SHIFT) {
            KeyEvent {
                code: KeyCode::BackTab,
                ..key
            }
        } else {
            key
        };
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return false;
        }
        if matches!(self.mode, Mode::Browsing) && self.focus == Focus::Filter {
            match key.code {
                KeyCode::Tab | KeyCode::Down => {
                    self.focus_contents();
                    return true;
                }
                KeyCode::BackTab | KeyCode::Up => {
                    self.focus_sources();
                    return true;
                }
                KeyCode::Enter | KeyCode::Char(' ') => {
                    self.toggle_filter();
                    return true;
                }
                _ => {}
            }
        }
        if matches!(self.mode, Mode::Browsing) && self.focus == Focus::Controls {
            match key.code {
                KeyCode::Right | KeyCode::Down => {
                    self.control_focus = (self.control_focus + 1) % 6;
                    return true;
                }
                KeyCode::Left => {
                    self.control_focus = (self.control_focus + 5) % 6;
                    return true;
                }
                KeyCode::Up => {
                    self.focus_contents();
                    return true;
                }
                KeyCode::Tab if self.control_focus < 5 => {
                    self.control_focus += 1;
                    return true;
                }
                KeyCode::Tab => {
                    self.focus_sources();
                    return true;
                }
                KeyCode::BackTab if self.control_focus > 0 => {
                    self.control_focus -= 1;
                    return true;
                }
                KeyCode::BackTab => {
                    self.focus_contents();
                    return true;
                }
                KeyCode::Enter | KeyCode::Char(' ') => {
                    match self.control_focus {
                        0 => self.confirm_batch(),
                        1 => self.selected_scripts.clear(),
                        2 => self.stop_on_error = !self.stop_on_error,
                        3 => self.parent(),
                        4 => {
                            if let Some(url) = self.current.clone() {
                                self.action(Action::Open(url));
                            }
                        }
                        _ => return false,
                    }
                    return true;
                }
                _ => {}
            }
        }
        let mode = std::mem::replace(&mut self.mode, Mode::Browsing);
        match mode {
            Mode::Browsing => match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return false,
                KeyCode::Tab => {
                    if self.focus == Focus::Sources {
                        self.focus = Focus::Filter;
                    } else {
                        self.focus = Focus::Controls;
                        self.control_focus = 0;
                    }
                }
                KeyCode::BackTab => {
                    if self.focus == Focus::Sources {
                        self.focus = Focus::Controls;
                        self.control_focus = 5;
                    } else {
                        self.focus = Focus::Filter;
                    }
                }
                KeyCode::Left if self.focus == Focus::Sources => self.move_source(-1),
                KeyCode::Right if self.focus == Focus::Sources => self.move_source(1),
                KeyCode::Enter | KeyCode::Char(' ') if self.focus == Focus::Sources => {
                    self.choose_source()
                }
                KeyCode::Down | KeyCode::Char('j') if self.focus == Focus::Sources => {
                    self.focus_contents()
                }
                KeyCode::Up | KeyCode::Char('k') if self.focus == Focus::Sources => {}
                KeyCode::Up | KeyCode::Char('k') if self.state.selected().unwrap_or(0) == 0 => {
                    self.focus_sources()
                }
                KeyCode::Up | KeyCode::Char('k') => self.move_selection(-1),
                KeyCode::Down
                    if self
                        .state
                        .selected()
                        .is_some_and(|i| i + 1 == self.entries.len()) =>
                {
                    self.focus = Focus::Controls;
                    self.control_focus = 0;
                }
                KeyCode::Down | KeyCode::Char('j') => self.move_selection(1),
                KeyCode::Enter | KeyCode::Right => self.select(),
                KeyCode::Char(' ') => self.toggle_script(),
                KeyCode::Char('x') => self.confirm_batch(),
                KeyCode::Char('i') => self.icons = !self.icons,
                KeyCode::Char('t') => self.toggle_filter(),
                KeyCode::PageUp => {
                    self.description_scroll = self.description_scroll.saturating_sub(3)
                }
                KeyCode::PageDown => {
                    self.description_scroll = self.description_scroll.saturating_add(3)
                }
                KeyCode::Char('c') => self.selected_scripts.clear(),
                KeyCode::Char('e') => self.stop_on_error = !self.stop_on_error,
                KeyCode::Backspace | KeyCode::Left => self.parent(),
                KeyCode::Char('r') => {
                    if let Some(url) = self.current.clone() {
                        self.action(Action::Open(url));
                    }
                }
                KeyCode::Char('o') => self.edit_location(),
                KeyCode::Char('2') => self.select_source(Source::Http),
                KeyCode::Char('1') => self.select_source(Source::Local),
                KeyCode::Char('3') => self.select_source(Source::Github),
                _ => {}
            },
            Mode::Url => match self.auth_key(key) {
                Some(true) => match if self.input_source == Source::Github {
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
                        self.auth_focus = 0;
                        self.mode = Mode::Url;
                    }
                },
                Some(false) => {
                    if self.current.is_some() {
                        self.focus_sources();
                        self.mode = Mode::Browsing;
                    } else {
                        return false;
                    }
                }
                None => {
                    self.message.clear();
                    self.mode = Mode::Url;
                }
            },
            Mode::Username(action) => match self.auth_key(key) {
                Some(true) => {
                    let username = self.input.take();
                    self.auth_focus = 0;
                    self.mode = Mode::Password(action, username);
                }
                Some(false) => self.cancel_auth(),
                None => self.mode = Mode::Username(action),
            },
            Mode::Password(action, username) => match self.auth_key(key) {
                Some(true) => {
                    let password = self.input.take();
                    let scope = match &action {
                        Action::Open(url) | Action::OpenRoot(url) => url.clone(),
                        Action::Run(entry) | Action::RunBatch(entry) => {
                            entry.url.join("./").expect("file URL has a parent")
                        }
                    };
                    self.repo.authenticate(scope, username, password);
                    self.action(action);
                    self.load_descriptions();
                }
                Some(false) => self.cancel_auth(),
                None => self.mode = Mode::Password(action, username),
            },
            Mode::Confirm(entry) => match key.code {
                KeyCode::Esc => {}
                KeyCode::Char('o' | 'O' | 'y' | 'Y') => self.action(Action::Run(entry)),
                KeyCode::Enter | KeyCode::Char(' ') if self.dialog_focus == 0 => {
                    self.action(Action::Run(entry))
                }
                KeyCode::Enter | KeyCode::Char(' ') => {}
                KeyCode::Left
                | KeyCode::Right
                | KeyCode::Up
                | KeyCode::Down
                | KeyCode::Tab
                | KeyCode::BackTab => {
                    self.dialog_focus = 1 - self.dialog_focus;
                    self.mode = Mode::Confirm(entry);
                }
                _ => self.mode = Mode::Confirm(entry),
            },
            Mode::ConfirmBatch => match key.code {
                KeyCode::Char('o' | 'O' | 'y' | 'Y') => self.start_batch(),
                KeyCode::Enter | KeyCode::Char(' ') if self.dialog_focus == 0 => self.start_batch(),
                KeyCode::Enter | KeyCode::Char(' ') if self.dialog_focus == 1 => {}
                KeyCode::Enter | KeyCode::Char(' ') | KeyCode::Char('e') => {
                    self.stop_on_error = !self.stop_on_error;
                    self.mode = Mode::ConfirmBatch;
                }
                KeyCode::Right | KeyCode::Tab => {
                    self.dialog_focus = (self.dialog_focus + 1) % 3;
                    self.mode = Mode::ConfirmBatch;
                }
                KeyCode::Left | KeyCode::BackTab => {
                    self.dialog_focus = (self.dialog_focus + 2) % 3;
                    self.mode = Mode::ConfirmBatch;
                }
                KeyCode::Down | KeyCode::PageDown => {
                    self.batch_scroll =
                        (self.batch_scroll + 1).min(self.selected_scripts.len().saturating_sub(1));
                    self.mode = Mode::ConfirmBatch;
                }
                KeyCode::Up | KeyCode::PageUp => {
                    self.batch_scroll = self.batch_scroll.saturating_sub(1);
                    self.mode = Mode::ConfirmBatch;
                }
                KeyCode::Esc => {}
                _ => self.mode = Mode::ConfirmBatch,
            },
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

fn script_command(interpreter: &Path, script_path: &Path, is_ps: bool, windows: bool) -> Command {
    let mut command = Command::new(interpreter);
    if is_ps {
        command.arg("-NoProfile");
        if windows {
            // Scope the override to the PowerShell process that runs this script.
            command.args(["-ExecutionPolicy", "Bypass"]);
        }
        command.arg("-File");
    }
    command.arg(script_path);
    command
}

fn prepare_script(
    entry: &Entry,
    data: &[u8],
) -> Result<(Command, Option<tempfile::TempDir>), String> {
    let is_ps = description::leaf(entry)
        .to_ascii_lowercase()
        .ends_with(".ps1");
    let local_path = entry.url.to_file_path().ok();
    let temporary = if local_path.is_none() {
        let dir = tempfile::Builder::new()
            .prefix("myeasytoolkit-")
            .tempdir()
            .map_err(|e| e.to_string())?;
        let path = dir
            .path()
            .join(if is_ps { "script.ps1" } else { "script.sh" });
        // Close the file before launching PowerShell on Windows.
        std::fs::write(&path, data).map_err(|e| e.to_string())?;
        Some((dir, path))
    } else {
        None
    };
    let path = local_path
        .as_deref()
        .or_else(|| temporary.as_ref().map(|(_, path)| path.as_path()))
        .ok_or_else(|| "Chemin du script indisponible.".to_owned())?;
    let interpreters = Interpreters::detect();
    let interpreter = if is_ps {
        interpreters.powershell
    } else {
        interpreters.bash
    }
    .ok_or_else(|| {
        if is_ps {
            "PowerShell est introuvable."
        } else {
            "Bash est introuvable."
        }
        .to_owned()
    })?;
    let command = script_command(&interpreter, path, is_ps, cfg!(windows));
    Ok((command, temporary.map(|(dir, _)| dir)))
}

#[cfg(test)]
fn execute_script(entry: &Entry, data: &[u8]) -> Result<(), String> {
    let (mut command, _temporary) = prepare_script(entry, data)?;
    let status = command.status().map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("code de sortie : {status}"))
    }
}

fn run_script(
    entry: &Entry,
    data: &[u8],
    wait_for_user: bool,
    pause_on_error: bool,
) -> Result<(), String> {
    let (command, _temporary) = prepare_script(entry, data)?;
    console::run(
        &location_label(&entry.url),
        &command,
        wait_for_user,
        pause_on_error,
    )
}

struct UiAreas {
    header: Rect,
    sources: Rect,
    location: Rect,
    filter: Rect,
    list: Rect,
    description: Rect,
    selection: Option<Rect>,
    batch_bar: Rect,
    footer: Rect,
}
impl UiAreas {
    fn new(area: Rect) -> Self {
        let parts = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(if area.height < 28 { 1 } else { 2 }),
                Constraint::Length(if area.height < 28 { 1 } else { 2 }),
                Constraint::Length(3),
                Constraint::Length(1),
                Constraint::Min(3),
                Constraint::Length(if area.height >= 28 {
                    7
                } else if area.height >= 20 {
                    5
                } else if area.height >= 16 {
                    4
                } else if area.height >= 11 {
                    3
                } else {
                    0
                }),
                Constraint::Length(2),
                Constraint::Length(2),
            ])
            .split(area);
        let (list, selection) = if parts[4].width >= 92 && parts[4].height >= 8 {
            let columns = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([
                    Constraint::Min(45),
                    Constraint::Length(1),
                    Constraint::Length(30),
                ])
                .split(parts[4]);
            (columns[0], Some(columns[2]))
        } else {
            (parts[4], None)
        };
        Self {
            header: parts[0],
            sources: parts[1],
            location: parts[2],
            filter: parts[3],
            list,
            description: parts[5],
            selection,
            batch_bar: parts[6],
            footer: parts[7],
        }
    }
}

// Keep the end of long locations visible without splitting UTF-8 characters.
fn compact_location(text: &str, width: usize) -> String {
    if UnicodeWidthStr::width(text) <= width {
        return text.to_string();
    }
    if width == 0 {
        return String::new();
    }
    let available = width - 1;
    let prefix_width = available / 3;
    let suffix_width = available - prefix_width;
    let mut prefix = String::new();
    let mut used = 0;
    for c in text.chars() {
        let w = UnicodeWidthChar::width(c).unwrap_or(0);
        if used + w > prefix_width {
            break;
        }
        prefix.push(c);
        used += w;
    }
    let mut suffix = Vec::new();
    used = 0;
    for c in text.chars().rev() {
        let w = UnicodeWidthChar::width(c).unwrap_or(0);
        if used + w > suffix_width {
            break;
        }
        suffix.push(c);
        used += w;
    }
    format!(
        "{}…{}",
        prefix,
        suffix.into_iter().rev().collect::<String>()
    )
}
fn wrap_description(text: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return vec![];
    }
    let mut lines = Vec::new();
    for paragraph in text.split('\n') {
        let mut line = String::new();
        let mut used = 0;
        for c in paragraph.chars() {
            let w = UnicodeWidthChar::width(c).unwrap_or(0);
            if used + w > width && !line.is_empty() {
                lines.push(std::mem::take(&mut line));
                used = 0;
            }
            if w <= width {
                line.push(c);
                used += w;
            }
        }
        lines.push(line);
    }
    lines
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
fn batch_popup_area(area: Rect) -> Rect {
    let width = area.width.saturating_sub(2).min(90);
    let height = area.height.saturating_sub(2).min(18);
    Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    )
}
fn dialog_buttons(width: u16, authentication: bool) -> (&'static str, &'static str, &'static str) {
    if width < 30 {
        if authentication {
            ("[OK]", "[Annul.]", " ")
        } else {
            ("[Oui]", "[Non]", " ")
        }
    } else if authentication {
        ("[Continuer]", "[Annuler]", "   ")
    } else {
        ("[Exécuter]", "[Annuler]", "   ")
    }
}

fn contains(area: Rect, x: u16, y: u16) -> bool {
    x >= area.x && x < area.right() && y >= area.y && y < area.bottom()
}
fn source_layout(area: Rect) -> (&'static str, [&'static str; 3], &'static str, [Rect; 3]) {
    let prefix = if area.width >= 54 {
        " Choisir une source : "
    } else {
        " "
    };
    let labels = if area.width < 28 {
        ["[1 L]", "[2 H]", "[3 G]"]
    } else if area.width < 32 {
        ["[1 Local]", "[2 HTTP]", "[3 Git]"]
    } else {
        ["[1 Local]", "[2 HTTP]", "[3 GitHub]"]
    };
    let gap = if area.width < 32 { " " } else { "  " };
    let mut x = area.x.saturating_add(UnicodeWidthStr::width(prefix) as u16);
    let mut bounds = [Rect::default(); 3];
    for (index, label) in labels.iter().enumerate() {
        let width = (UnicodeWidthStr::width(*label) as u16).min(area.right().saturating_sub(x));
        bounds[index] = Rect::new(x.min(area.right()), area.y, width, area.height.min(1));
        x = x.saturating_add(
            UnicodeWidthStr::width(*label) as u16 + UnicodeWidthStr::width(gap) as u16,
        );
    }
    (prefix, labels, gap, bounds)
}

fn draw(frame: &mut Frame, app: &mut App) {
    let areas = UiAreas::new(frame.area());
    let accent = Style::default().add_modifier(Modifier::BOLD);
    let focused = |selected: bool| {
        if selected {
            accent.add_modifier(Modifier::REVERSED)
        } else {
            accent
        }
    };
    let heading = " MyEasyToolkit  /  vos scripts en un seul endroit";
    let mut header = vec![Span::styled(" MyEasyToolkit", accent)];
    if areas.header.width >= 50 {
        header.push(Span::raw("  /  vos scripts en un seul endroit"));
    }
    if areas.header.width >= 72 {
        let version = format!("v{}  ", env!("CARGO_PKG_VERSION"));
        let gap = usize::from(areas.header.width).saturating_sub(
            UnicodeWidthStr::width(heading) + UnicodeWidthStr::width(version.as_str()),
        );
        header.push(Span::raw(" ".repeat(gap)));
        header.push(Span::styled(version, Style::default()));
    }
    frame.render_widget(Paragraph::new(Line::from(header)), areas.header);
    let active = if matches!(app.mode, Mode::Url) {
        app.input_source
    } else {
        app.current.as_ref().map_or(Source::Local, source_for)
    };
    let source_style = |source| {
        if matches!(app.mode, Mode::Browsing)
            && app.focus == Focus::Sources
            && app.source_cursor == source
        {
            // Reverse video remains visible in terminals that disable color.
            Style::default().add_modifier(Modifier::BOLD | Modifier::REVERSED)
        } else if active == source {
            Style::default().add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
        } else {
            Style::default()
        }
    };
    let (prefix, labels, gap, _) = source_layout(areas.sources);
    let sources = Line::from(vec![
        Span::raw(prefix),
        Span::styled(labels[0], source_style(Source::Local)),
        Span::raw(gap),
        Span::styled(labels[1], source_style(Source::Http)),
        Span::raw(gap),
        Span::styled(labels[2], source_style(Source::Github)),
    ]);
    frame.render_widget(Paragraph::new(sources), areas.sources);
    let editing = matches!(app.mode, Mode::Url);
    let title = if editing {
        if app.input_source == Source::Github {
            " Dépôt GitHub public · Entrée pour ouvrir "
        } else {
            " Adresse HTTP · Entrée pour ouvrir "
        }
    } else if app
        .current
        .as_ref()
        .is_some_and(|url| source_for(url) != Source::Local)
    {
        " Emplacement · cliquer pour modifier "
    } else {
        " Emplacement actuel "
    };
    frame.render_widget(
        Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(if editing { accent } else { Style::default() }),
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
            let padding =
                usize::from(field.width).saturating_sub(UnicodeWidthStr::width(text.as_str()));
            frame.render_widget(
                Paragraph::new(format!("{text}{}", " ".repeat(padding)))
                    .style(Style::default().add_modifier(Modifier::UNDERLINED)),
                field,
            );
            if app.auth_focus == 0 {
                frame.set_cursor_position((field.x + caret as u16, field.y));
            }
        } else {
            let text = app
                .current
                .as_ref()
                .map_or_else(|| "Choisissez une source".to_string(), location_label);
            frame.render_widget(
                Paragraph::new(compact_location(&text, field.width as usize)),
                field,
            );
        }
    }
    let filter = if app.show_all {
        " [t Filtre]  Tous les fichiers"
    } else {
        " [t Filtre]  Compatibles"
    };
    frame.render_widget(
        Paragraph::new(filter).style(focused(
            matches!(app.mode, Mode::Browsing) && app.focus == Focus::Filter,
        )),
        areas.filter,
    );
    let items: Vec<ListItem> = app
        .entries
        .iter()
        .map(|entry| {
            let kind = match (app.icons, entry.directory, is_script(entry)) {
                (true, true, _) => "📁  ",
                (true, false, true) => "📜  ",
                (true, false, false) => "📄  ",
                (false, true, _) => "[D] ",
                (false, false, true) => "[S] ",
                _ => "[F] ",
            };
            let selection = if is_script(entry) {
                app.selected_scripts
                    .iter()
                    .position(|item| item.url == entry.url)
                    .map_or_else(|| " [  ] ".to_string(), |i| format!(" [{:>2}] ", i + 1))
            } else {
                "      ".to_string()
            };
            let mut spans = vec![
                Span::styled(selection, Style::default().add_modifier(Modifier::BOLD)),
                Span::styled(
                    kind,
                    if entry.directory {
                        Style::default().add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    },
                ),
                Span::raw(&entry.name),
            ];
            if areas.list.width >= 55 {
                if let Some(Ok(text)) = app.description(entry) {
                    if let Some(summary) = text.lines().find(|line| !line.trim().is_empty()) {
                        let used = UnicodeWidthStr::width(entry.name.as_str()) + 12;
                        let column = (usize::from(areas.list.width) * 2 / 5).max(28);
                        if used < column {
                            spans.push(Span::raw(" ".repeat(column - used)));
                            spans.push(Span::styled(
                                compact_location(
                                    summary,
                                    usize::from(areas.list.width).saturating_sub(column + 3),
                                ),
                                Style::default(),
                            ));
                        }
                    }
                }
            }
            ListItem::new(Line::from(spans))
        })
        .collect();
    let list_title = if areas.list.width < 55 {
        format!(" Contenu · {} ", app.entries.len())
    } else {
        format!(
            " Contenu · {} élément(s) · {} dossier · {} script ",
            app.entries.len(),
            if app.icons { "📁" } else { "[D]" },
            if app.icons { "📜" } else { "[S]" }
        )
    };
    let list = List::new(items)
        .block(
            Block::default()
                .title(list_title)
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(if app.focus == Focus::Contents {
                    accent
                } else {
                    Style::default()
                }),
        )
        .highlight_style(if app.focus == Focus::Contents {
            Style::default().add_modifier(Modifier::BOLD | Modifier::REVERSED)
        } else {
            Style::default()
        })
        .highlight_symbol(if app.focus == Focus::Contents {
            "›"
        } else {
            " "
        });
    frame.render_stateful_widget(list, areas.list, &mut app.state);
    let description_title = if areas.description.width >= 44 {
        " Description · Pg↑/Pg↓ · [↑] [↓] "
    } else {
        " Description [↑] [↓] "
    };
    frame.render_widget(
        Block::default()
            .title(description_title)
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(Style::default()),
        areas.description,
    );
    if areas.description.width > 2 && areas.description.height > 2 {
        let inner = Rect::new(
            areas.description.x + 1,
            areas.description.y + 1,
            areas.description.width - 2,
            areas.description.height - 2,
        );
        let lines = wrap_description(&app.description_text(), usize::from(inner.width));
        app.description_scroll = app
            .description_scroll
            .min(lines.len().saturating_sub(usize::from(inner.height)));
        frame.render_widget(
            Paragraph::new(
                lines
                    .into_iter()
                    .skip(app.description_scroll)
                    .take(usize::from(inner.height))
                    .map(Line::raw)
                    .collect::<Vec<_>>(),
            ),
            inner,
        );
    }
    if let Some(panel) = areas.selection {
        frame.render_widget(
            Block::default()
                .title(format!(" Sélection · {} ", app.selected_scripts.len()))
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default()),
            panel,
        );
        if panel.width > 4 && panel.height > 3 {
            let inner = Rect::new(panel.x + 2, panel.y + 1, panel.width - 4, panel.height - 2);
            let detail_height = if inner.height >= 9 { 4 } else { 0 };
            let queue_height = inner.height.saturating_sub(detail_height);
            let mut lines = Vec::new();
            if app.selected_scripts.is_empty() {
                lines.push(Line::styled(
                    "Aucun script choisi",
                    Style::default().add_modifier(Modifier::BOLD),
                ));
                lines.push(Line::raw(""));
                lines.push(Line::raw("Cochez un script ou"));
                lines.push(Line::raw("utilisez Espace."));
            } else {
                let capacity = usize::from(queue_height);
                let shown = if app.selected_scripts.len() > capacity {
                    capacity.saturating_sub(1)
                } else {
                    capacity
                };
                for (index, entry) in app.selected_scripts.iter().take(shown).enumerate() {
                    lines.push(Line::from(vec![
                        Span::styled(
                            format!("{:>2}  ", index + 1),
                            Style::default().add_modifier(Modifier::BOLD),
                        ),
                        Span::raw(entry.name.as_str()),
                    ]));
                }
                if shown < app.selected_scripts.len() {
                    lines.push(Line::styled(
                        format!("+ {} autre(s) · Lancer", app.selected_scripts.len() - shown),
                        Style::default(),
                    ));
                }
            }
            frame.render_widget(
                Paragraph::new(lines),
                Rect::new(inner.x, inner.y, inner.width, queue_height),
            );
            if detail_height > 0 {
                let entry = app
                    .state
                    .selected()
                    .and_then(|index| app.entries.get(index));
                let mut details = vec![Line::styled(
                    "Élément actif",
                    Style::default().add_modifier(Modifier::BOLD),
                )];
                if let Some(entry) = entry {
                    details.push(Line::raw(entry.name.as_str()));
                    details.push(Line::raw(if entry.directory {
                        "Dossier · Entrée : ouvrir"
                    } else if is_script(entry) {
                        "Script · Entrée : ouvrir"
                    } else {
                        "Fichier non pris en charge"
                    }));
                } else {
                    details.push(Line::raw("Aucun élément"));
                }
                frame.render_widget(
                    Paragraph::new(details),
                    Rect::new(inner.x, inner.bottom() - 3, inner.width, 3),
                );
            }
        }
    }
    if app.entries.is_empty()
        && app.current.is_some()
        && areas.list.width > 2
        && areas.list.height > 2
    {
        frame.render_widget(
            Paragraph::new("Aucun fichier ni dossier trouvé.").style(Style::default()),
            Rect::new(areas.list.x + 1, areas.list.y + 1, areas.list.width - 2, 1),
        );
    }
    let compact = areas.batch_bar.width < 38;
    let batch_line = Line::from(vec![
        Span::raw(" "),
        Span::styled(
            if compact { "[Lancer]" } else { "[Lancer x]" },
            focused(app.focus == Focus::Controls && app.control_focus == 0),
        ),
        Span::raw(" "),
        Span::styled(
            if compact { "[Vider]" } else { "[Vider c]" },
            focused(app.focus == Focus::Controls && app.control_focus == 1),
        ),
        Span::raw(format!(
            "  {} script(s) en attente",
            app.selected_scripts.len()
        )),
    ]);
    let stop_line = Line::from(vec![
        Span::raw(" "),
        Span::styled(
            format!(
                "[{}] Arrêter si erreur (e)",
                if app.stop_on_error { "x" } else { " " }
            ),
            focused(app.focus == Focus::Controls && app.control_focus == 2),
        ),
    ]);
    frame.render_widget(Paragraph::new(vec![batch_line, stop_line]), areas.batch_bar);
    let actions = if editing {
        let compact = areas.footer.width < 20;
        Line::from(vec![
            Span::raw(" "),
            Span::styled(
                if compact { "[OK]" } else { "[Ouvrir]" },
                focused(app.auth_focus == 1),
            ),
            Span::raw(if compact { " " } else { "  " }),
            Span::styled("[Annuler]", focused(app.auth_focus == 2)),
        ])
    } else {
        let compact = areas.footer.width < 34;
        Line::from(vec![
            Span::raw(" "),
            Span::styled(
                "[Retour]",
                focused(app.focus == Focus::Controls && app.control_focus == 3),
            ),
            Span::raw(if compact { " " } else { "  " }),
            Span::styled(
                if compact { "[Maj]" } else { "[Actualiser]" },
                focused(app.focus == Focus::Controls && app.control_focus == 4),
            ),
            Span::raw(if compact { " " } else { "  " }),
            Span::styled(
                if areas.footer.width < 26 {
                    "[Quit]"
                } else {
                    "[Quitter]"
                },
                focused(app.focus == Focus::Controls && app.control_focus == 5),
            ),
        ])
    };
    let hint = if editing {
        if app.message.is_empty() {
            "Entrée : ouvrir · Tab : boutons · ←/→ : curseur"
        } else {
            app.message.as_str()
        }
    } else if app.focus == Focus::Controls {
        "←/→ : action · Entrée : valider · ↑ : fichiers"
    } else if app.focus == Focus::Filter {
        "Entrée : changer le filtre · ↓ : fichiers"
    } else if app.focus == Focus::Sources {
        if areas.footer.width < 38 {
            "←/→ source · Entrée · ↓"
        } else {
            "←/→ : source  ·  Entrée : choisir  ·  ↓ : fichiers"
        }
    } else if areas.footer.width < 38 {
        "↑ en haut : sources · Espace"
    } else if areas.footer.width < 72 {
        "↑ en haut : sources · Espace : choisir"
    } else {
        "↑/↓ : fichiers · Espace : choisir · Entrée : ouvrir · i : icônes"
    };
    frame.render_widget(
        Paragraph::new(vec![
            actions,
            Line::styled(
                hint,
                if editing && !app.message.is_empty() {
                    Style::default().add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                },
            ),
        ]),
        areas.footer,
    );

    let input_prompt = match &app.mode {
        Mode::Username(_) => Some((" Connexion au dépôt ", "Identifiant", false)),
        Mode::Password(_, _) => Some((" Connexion au dépôt ", "Mot de passe", true)),
        _ => None,
    };
    if matches!(app.mode, Mode::ConfirmBatch) {
        let popup = batch_popup_area(frame.area());
        frame.render_widget(Clear, popup);
        frame.render_widget(
            Block::default()
                .title(" Confirmer la sélection ")
                .borders(Borders::ALL)
                .border_style(accent),
            popup,
        );
        if popup.width > 4 && popup.height >= 6 {
            let width = popup.width - 4;
            let visible = usize::from(popup.height.saturating_sub(5));
            let max_scroll = app.selected_scripts.len().saturating_sub(visible);
            app.batch_scroll = app.batch_scroll.min(max_scroll);
            let lines: Vec<Line> = app
                .selected_scripts
                .iter()
                .enumerate()
                .skip(app.batch_scroll)
                .take(visible)
                .map(|(i, entry)| {
                    Line::raw(format!(
                        "{}. {} · {}",
                        i + 1,
                        entry.name,
                        location_label(&entry.url)
                    ))
                })
                .collect();
            frame.render_widget(
                Paragraph::new(lines),
                Rect::new(popup.x + 2, popup.y + 1, width, visible as u16),
            );
            frame.render_widget(
                Paragraph::new(format!(
                    "[{}] Arrêter si erreur (e)",
                    if app.stop_on_error { "x" } else { " " }
                ))
                .style(focused(app.dialog_focus == 2)),
                Rect::new(popup.x + 2, popup.bottom() - 4, width, 1),
            );
            let (primary, cancel, _) = dialog_buttons(popup.width, false);
            let gap = " ";
            frame.render_widget(
                Paragraph::new(Line::from(vec![
                    Span::styled(primary, focused(app.dialog_focus == 0)),
                    Span::raw(gap),
                    Span::styled(cancel, focused(app.dialog_focus == 1)),
                    Span::raw("  ←/→ choix · Entrée · ↑/↓ liste"),
                ])),
                Rect::new(popup.x + 2, popup.bottom() - 2, width, 1),
            );
        }
    } else if let Some((title, label, secret)) = input_prompt {
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
            let padding =
                usize::from(inner_width).saturating_sub(UnicodeWidthStr::width(text.as_str()));
            frame.render_widget(
                Paragraph::new(format!("{text}{}", " ".repeat(padding)))
                    .style(Style::default().add_modifier(Modifier::UNDERLINED)),
                Rect::new(x, y + 1, inner_width, 1),
            );
            if app.auth_focus == 0 {
                frame.set_cursor_position((x + caret as u16, y + 1));
            }
            if popup.height >= 6 {
                let (primary, cancel, gap) = dialog_buttons(popup.width, true);
                frame.render_widget(
                    Paragraph::new(Line::from(vec![
                        Span::styled(primary, focused(app.auth_focus == 1)),
                        Span::raw(gap),
                        Span::styled(cancel, focused(app.auth_focus == 2)),
                        Span::raw("  Tab : choix"),
                    ])),
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
            Mode::Message => Some((" Information ", format!("{}\n\n[Fermer]", app.message))),
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
                let (primary, cancel, gap) = dialog_buttons(popup.width, false);
                frame.render_widget(
                    Paragraph::new(Line::from(vec![
                        Span::styled(primary, focused(app.dialog_focus == 0)),
                        Span::raw(gap),
                        Span::styled(cancel, focused(app.dialog_focus == 1)),
                        Span::raw("   ←/→ : choisir · Entrée"),
                    ])),
                    Rect::new(popup.x + 2, popup.bottom() - 2, popup.width - 4, 1),
                );
            }
        }
    }
}

fn mouse(app: &mut App, mouse: crossterm::event::MouseEvent, area: Rect) -> bool {
    let areas = UiAreas::new(area);
    match mouse.kind {
        MouseEventKind::ScrollDown if matches!(app.mode, Mode::ConfirmBatch) => {
            app.key(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE));
        }
        MouseEventKind::ScrollUp if matches!(app.mode, Mode::ConfirmBatch) => {
            app.key(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
        }
        MouseEventKind::ScrollDown
            if matches!(app.mode, Mode::Browsing)
                && contains(areas.description, mouse.column, mouse.row) =>
        {
            app.description_scroll = app.description_scroll.saturating_add(3)
        }
        MouseEventKind::ScrollUp
            if matches!(app.mode, Mode::Browsing)
                && contains(areas.description, mouse.column, mouse.row) =>
        {
            app.description_scroll = app.description_scroll.saturating_sub(3)
        }
        MouseEventKind::ScrollDown if matches!(app.mode, Mode::Browsing) => {
            app.focus_contents();
            app.move_selection(1);
        }
        MouseEventKind::ScrollUp if matches!(app.mode, Mode::Browsing) => {
            app.focus_contents();
            app.move_selection(-1);
        }
        MouseEventKind::Down(crossterm::event::MouseButton::Left) => {
            let x = mouse.column;
            let y = mouse.row;
            if matches!(app.mode, Mode::Browsing)
                && y == areas.filter.y
                && x > areas.filter.x
                && x < areas.filter.x.saturating_add(11).min(areas.filter.right())
            {
                app.focus = Focus::Filter;
                app.toggle_filter();
            } else if matches!(app.mode, Mode::Browsing)
                && y == areas.description.y
                && areas.description.width >= 22
            {
                let title = if areas.description.width >= 44 {
                    " Description · Pg↑/Pg↓ · [↑] [↓] "
                } else {
                    " Description [↑] [↓] "
                };
                let up = UnicodeWidthStr::width(title.split("[↑]").next().unwrap_or("")) as u16;
                let relative = x.saturating_sub(areas.description.x + 1);
                if relative >= up && relative < up + 3 {
                    app.description_scroll = app.description_scroll.saturating_sub(3);
                } else if relative >= up + 4 && relative < up + 7 {
                    app.description_scroll = app.description_scroll.saturating_add(3);
                }
            } else if matches!(app.mode, Mode::Browsing)
                && areas.batch_bar.height > 0
                && y == areas.batch_bar.y
            {
                let col = x.saturating_sub(areas.batch_bar.x);
                if areas.batch_bar.width < 38 && (1..=8).contains(&col) {
                    app.confirm_batch();
                } else if areas.batch_bar.width < 38 && (10..=16).contains(&col) {
                    app.selected_scripts.clear();
                } else if areas.batch_bar.width >= 38 && (1..=10).contains(&col) {
                    app.confirm_batch();
                } else if areas.batch_bar.width >= 38 && (12..=20).contains(&col) {
                    app.selected_scripts.clear();
                }
            } else if matches!(app.mode, Mode::Browsing)
                && areas.batch_bar.height > 1
                && y == areas.batch_bar.y + 1
                && x > areas.batch_bar.x
                && x < areas
                    .batch_bar
                    .right()
                    .min(areas.batch_bar.x.saturating_add(27))
            {
                app.stop_on_error = !app.stop_on_error;
            } else if matches!(app.mode, Mode::Browsing | Mode::Url)
                && areas.footer.height > 0
                && y == areas.footer.y
                && x >= areas.footer.x
            {
                let col = x - areas.footer.x;
                if matches!(app.mode, Mode::Url) {
                    if areas.footer.width < 20 {
                        if (1..=4).contains(&col) {
                            app.auth_focus = 1;
                            return app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
                        }
                        if (6..=14).contains(&col) {
                            return app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
                        }
                    } else {
                        if (1..=8).contains(&col) {
                            app.auth_focus = 1;
                            return app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
                        }
                        if (11..=19).contains(&col) {
                            return app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
                        }
                    }
                } else if areas.footer.width < 34 {
                    if (1..=8).contains(&col) {
                        app.parent();
                    } else if (10..=14).contains(&col) {
                        if let Some(url) = app.current.clone() {
                            app.action(Action::Open(url));
                        }
                    } else if (16..=24).contains(&col) {
                        return false;
                    }
                } else if (1..=8).contains(&col) {
                    app.parent();
                } else if (11..=22).contains(&col) {
                    if let Some(url) = app.current.clone() {
                        app.action(Action::Open(url));
                    }
                } else if (25..=33).contains(&col) {
                    return false;
                }
            } else if matches!(app.mode, Mode::Browsing | Mode::Url)
                && contains(areas.sources, x, y)
            {
                let (_, _, _, bounds) = source_layout(areas.sources);
                if let Some(index) = bounds.iter().position(|area| contains(*area, x, y)) {
                    app.select_source(SOURCES[index]);
                }
            } else if matches!(app.mode, Mode::Url)
                && areas.location.width > 2
                && y == areas.location.y + 1
                && x > areas.location.x
                && x < areas.location.right() - 1
            {
                app.auth_focus = 0;
                app.input.click(
                    (areas.location.width - 2) as usize,
                    (x - areas.location.x - 1) as usize,
                    false,
                );
            } else if matches!(app.mode, Mode::Browsing) && contains(areas.location, x, y) {
                if app
                    .current
                    .as_ref()
                    .is_some_and(|url| source_for(url) != Source::Local)
                {
                    app.edit_location();
                }
            } else if matches!(app.mode, Mode::Browsing)
                && x > areas.list.x
                && x < areas.list.right().saturating_sub(1)
                && y > areas.list.y
                && y < areas.list.bottom().saturating_sub(1)
            {
                let index = app.state.offset() + usize::from(y - areas.list.y - 1);
                if index < app.entries.len() {
                    app.focus_contents();
                    let already_focused = app.state.selected() == Some(index);
                    app.state.select(Some(index));
                    if x >= areas.list.x + 2
                        && x <= areas.list.x + 6
                        && is_script(&app.entries[index])
                    {
                        app.toggle_script();
                    } else if app.entries[index].directory || already_focused {
                        app.select();
                    }
                }
            } else if matches!(app.mode, Mode::Username(_) | Mode::Password(_, _)) {
                let popup = popup_area(area);
                if popup.width > 4
                    && popup.height >= 4
                    && y == popup.y + 2
                    && x >= popup.x + 2
                    && x < popup.right() - 2
                {
                    app.auth_focus = 0;
                    app.input.click(
                        (popup.width - 4) as usize,
                        (x - popup.x - 2) as usize,
                        matches!(app.mode, Mode::Password(_, _)),
                    );
                } else if popup.width > 4 && popup.height >= 6 && y == popup.y + 4 {
                    let (primary, cancel, gap) = dialog_buttons(popup.width, true);
                    let start = popup.x + 2;
                    let cancel_start = start
                        + UnicodeWidthStr::width(primary) as u16
                        + UnicodeWidthStr::width(gap) as u16;
                    if x >= start && x < start + UnicodeWidthStr::width(primary) as u16 {
                        app.auth_focus = 1;
                        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
                    } else if x >= cancel_start
                        && x < cancel_start + UnicodeWidthStr::width(cancel) as u16
                    {
                        return app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
                    }
                }
            } else if matches!(app.mode, Mode::ConfirmBatch) {
                let popup = batch_popup_area(area);
                if popup.width > 4
                    && popup.height >= 6
                    && y == popup.bottom() - 4
                    && x >= popup.x + 2
                    && x < popup.right() - 2
                {
                    app.dialog_focus = 2;
                    app.stop_on_error = !app.stop_on_error;
                } else if popup.width > 4 && popup.height >= 6 && y == popup.bottom() - 2 {
                    let (primary, cancel, _) = dialog_buttons(popup.width, false);
                    let gap = " ";
                    let start = popup.x + 2;
                    let cancel_start = start
                        + UnicodeWidthStr::width(primary) as u16
                        + UnicodeWidthStr::width(gap) as u16;
                    if x >= start && x < start + UnicodeWidthStr::width(primary) as u16 {
                        app.start_batch();
                    } else if x >= cancel_start
                        && x < cancel_start + UnicodeWidthStr::width(cancel) as u16
                    {
                        app.mode = Mode::Browsing;
                    }
                }
            } else if matches!(app.mode, Mode::Confirm(_)) {
                let popup = popup_area(area);
                if popup.width > 4 && popup.height >= 5 && y == popup.bottom() - 2 {
                    let (primary, cancel, gap) = dialog_buttons(popup.width, false);
                    let start = popup.x + 2;
                    let cancel_start = start
                        + UnicodeWidthStr::width(primary) as u16
                        + UnicodeWidthStr::width(gap) as u16;
                    if x >= start && x < start + UnicodeWidthStr::width(primary) as u16 {
                        app.key(KeyEvent::new(KeyCode::Char('o'), KeyModifiers::NONE));
                    } else if x >= cancel_start
                        && x < cancel_start + UnicodeWidthStr::width(cancel) as u16
                    {
                        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
                    }
                }
            } else if matches!(app.mode, Mode::Message) {
                app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
            }
        }
        _ => {}
    }
    true
}

// Returning from script execution switches back to an empty alternate screen.
// Reset Ratatui's previous frame as well, otherwise it only paints changed cells.
fn draw_app<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> io::Result<()> {
    if app.screen_needs_redraw {
        terminal.clear()?;
        app.screen_needs_redraw = false;
    }
    app.update_descriptions();
    terminal.draw(|frame| draw(frame, app))?;
    Ok(())
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
        if matches!(app.mode, Mode::Browsing) {
            app.focus_sources();
        }
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
            if app.batch.is_some() && matches!(app.mode, Mode::Browsing) {
                app.advance_batch();
                continue;
            }
            draw_app(&mut terminal, &mut app)?;
            if !event::poll(Duration::from_millis(100))? {
                continue;
            }
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
                    if app.auth_focus != 0 {
                        continue;
                    }
                    if matches!(app.mode, Mode::Url)
                        && (app.input.text == "https://" || app.input.text == "https://github.com/")
                        && text.trim_start().starts_with("http")
                    {
                        app.input.clear();
                    }
                    app.input.insert(&text);
                    app.message.clear();
                }
                Event::Mouse(event) if !mouse(&mut app, event, terminal.get_frame().area()) => {
                    break
                }
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

    #[test]
    fn script_command_scopes_windows_policy_to_the_powershell_child() {
        let interpreter = Path::new("interpreter path");
        let script = Path::new("script path/test.ps1");
        let args = |is_ps, windows| {
            script_command(interpreter, script, is_ps, windows)
                .get_args()
                .map(|arg| arg.to_os_string())
                .collect::<Vec<_>>()
        };
        assert_eq!(
            args(true, true),
            [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "script path/test.ps1"
            ]
        );
        assert_eq!(
            args(true, false),
            ["-NoProfile", "-File", "script path/test.ps1"]
        );
        assert_eq!(args(false, true), ["script path/test.ps1"]);
        assert_eq!(args(false, false), ["script path/test.ps1"]);
    }

    #[cfg(windows)]
    #[test]
    fn powershell_executes_selected_scripts_under_a_restricted_parent_policy() {
        const CHILD: &str = "MET_POLICY_TEST_CHILD";
        const MARKER: &str = "MET_POLICY_TEST_MARKER";
        if std::env::var_os(CHILD).is_none() {
            let dir = tempfile::tempdir().unwrap();
            for legacy in [false, true] {
                let marker = dir.path().join("script result.txt");
                let mut child = Command::new(std::env::current_exe().unwrap());
                child
                    .args([
                        "--exact",
                        "input_tests::powershell_executes_selected_scripts_under_a_restricted_parent_policy",
                        "--nocapture",
                    ])
                    .env(CHILD, if legacy { "legacy" } else { "default" })
                    .env(MARKER, &marker)
                    .env("PSExecutionPolicyPreference", "Restricted");
                if legacy {
                    let system_root = PathBuf::from(std::env::var_os("SystemRoot").unwrap());
                    let legacy_dir = system_root.join("System32/WindowsPowerShell/v1.0");
                    #[cfg(target_arch = "x86_64")]
                    assert!(
                        legacy_dir.join("powershell.exe").is_file(),
                        "Windows PowerShell 5.1 missing"
                    );
                    if !legacy_dir.join("powershell.exe").is_file() {
                        continue;
                    }
                    child.env(
                        "PATH",
                        std::env::join_paths([
                            legacy_dir,
                            system_root.join("System32"),
                            system_root,
                        ])
                        .unwrap(),
                    );
                    // GitHub runs cargo under pwsh 7, whose module path can
                    // otherwise be inherited by Windows PowerShell 5.1.
                    child.env_remove("PSModulePath");
                }
                let result = child.output().unwrap();
                assert!(
                    result.status.success(),
                    "child test failed (legacy={legacy}): {}\n{}",
                    String::from_utf8_lossy(&result.stdout),
                    String::from_utf8_lossy(&result.stderr)
                );
                std::fs::remove_file(marker).unwrap();
            }
            return;
        }

        let interpreter = Interpreters::detect()
            .powershell
            .expect("PowerShell required");
        if std::env::var(CHILD).unwrap() == "legacy" {
            assert_eq!(interpreter.file_name().unwrap(), "powershell.exe");
        }
        let parent_policy = || {
            let result = Command::new(&interpreter)
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    "Get-ExecutionPolicy",
                ])
                .output()
                .unwrap();
            assert!(
                result.status.success(),
                "Get-ExecutionPolicy failed: {}",
                String::from_utf8_lossy(&result.stderr)
            );
            String::from_utf8_lossy(&result.stdout).trim().to_owned()
        };
        assert_eq!(parent_policy(), "Restricted");
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("script avec espaces.ps1");
        let marker = PathBuf::from(std::env::var_os(MARKER).unwrap());
        let script = b"Set-Content -LiteralPath $env:MET_POLICY_TEST_MARKER -Value ((Get-ExecutionPolicy).ToString() + '|' + $PSCommandPath)\n";
        std::fs::write(&path, script).unwrap();
        let baseline = Command::new(&interpreter)
            .args(["-NoProfile", "-File"])
            .arg(&path)
            .output()
            .unwrap();
        assert!(!baseline.status.success());
        assert!(!marker.exists());

        let local = Entry {
            name: "script avec espaces.ps1".into(),
            url: Url::from_file_path(&path).unwrap(),
            directory: false,
        };
        execute_script(&local, b"").expect("local script should run");
        let local_result = std::fs::read_to_string(&marker).unwrap();
        let (policy, executed_path) = local_result.trim().split_once('|').unwrap();
        assert_eq!(policy, "Bypass");
        assert_eq!(
            std::fs::canonicalize(executed_path).unwrap(),
            std::fs::canonicalize(&path).unwrap()
        );
        std::fs::remove_file(&marker).unwrap();
        let remote = Entry {
            name: "script.ps1".into(),
            url: Url::parse("https://example.test/script.ps1").unwrap(),
            directory: false,
        };
        execute_script(&remote, script).expect("downloaded script should run");
        let remote_result = std::fs::read_to_string(&marker).unwrap();
        let (policy, executed_path) = remote_result.trim().split_once('|').unwrap();
        assert_eq!(policy, "Bypass");
        assert!(!Path::new(executed_path).exists());
        assert!(execute_script(&remote, b"exit 42\n").is_err());
        assert_eq!(parent_policy(), "Restricted");
    }

    fn press(input: &mut Input, key: KeyCode) {
        input.key(KeyEvent::new(key, KeyModifiers::NONE));
    }

    #[test]
    fn sources_can_be_chosen_and_contents_reached_with_arrows() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("dossier")).unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.focus_sources();
        let original = app.current.clone();
        assert_eq!(app.source_cursor, Source::Local);
        key(&mut app, KeyCode::Right);
        assert_eq!(app.source_cursor, Source::Http);
        assert_eq!(app.current, original);
        assert!(matches!(app.mode, Mode::Browsing));
        key(&mut app, KeyCode::Right);
        key(&mut app, KeyCode::Right);
        assert_eq!(app.source_cursor, Source::Github);
        key(&mut app, KeyCode::Enter);
        assert!(matches!(app.mode, Mode::Url));
        assert_eq!(app.input.text, "https://github.com/");
        key(&mut app, KeyCode::Esc);
        assert_eq!(app.focus, Focus::Sources);
        assert_eq!(app.source_cursor, Source::Local);
        assert_eq!(app.current, original);
        key(&mut app, KeyCode::Right);
        key(&mut app, KeyCode::Char(' '));
        assert_eq!(app.input.text, "https://");
        key(&mut app, KeyCode::Esc);
        key(&mut app, KeyCode::Down);
        assert_eq!(app.focus, Focus::Contents);
        assert_eq!(app.state.selected(), Some(0));
        key(&mut app, KeyCode::Up);
        assert_eq!(app.focus, Focus::Sources);
        key(&mut app, KeyCode::Enter);
        assert_eq!(app.focus, Focus::Contents);
        assert_eq!(app.current, original);
        key(&mut app, KeyCode::Right);
        assert!(app
            .current
            .as_ref()
            .unwrap()
            .to_file_path()
            .unwrap()
            .ends_with("dossier"));
        key(&mut app, KeyCode::Left);
        assert_eq!(app.current, original);
    }

    #[test]
    fn source_focus_is_distinct_from_the_active_source_and_list() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.focus_sources();
        let areas = UiAreas::new(Rect::new(0, 0, 80, 24));
        let (_, _, _, sources) = source_layout(areas.sources);
        let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        assert!(terminal.backend().buffer()[(sources[0].x, sources[0].y)]
            .modifier
            .contains(Modifier::REVERSED));
        key(&mut app, KeyCode::Right);
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        let buffer = terminal.backend().buffer();
        assert!(buffer[(sources[1].x, sources[1].y)]
            .modifier
            .contains(Modifier::REVERSED));
        assert!(buffer[(sources[0].x, sources[0].y)]
            .modifier
            .contains(Modifier::UNDERLINED));
        assert!(!buffer[(sources[0].x, sources[0].y)]
            .modifier
            .contains(Modifier::REVERSED));
        key(&mut app, KeyCode::Down);
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        assert!(!terminal.backend().buffer()[(sources[1].x, sources[1].y)]
            .modifier
            .contains(Modifier::REVERSED));
        assert_eq!(app.source_cursor, Source::Local);
    }

    #[test]
    fn source_labels_and_click_areas_follow_the_same_order_at_each_width() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        for width in [24, 28, 32, 54, 80] {
            let screen = Rect::new(0, 0, width, 24);
            let area = UiAreas::new(screen).sources;
            let (prefix, labels, _, bounds) = source_layout(area);
            if width >= 54 {
                assert!(prefix.contains("Choisir une source"));
            } else {
                assert_eq!(prefix, " ");
            }
            for i in 0..3 {
                assert!(bounds[i].width > 0);
                if i > 0 {
                    assert!(bounds[i - 1].right() < bounds[i].x);
                }
                let mut app = App::new().unwrap();
                let mut terminal = Terminal::new(TestBackend::new(width, 24)).unwrap();
                terminal.draw(|frame| draw(frame, &mut app)).unwrap();
                let row = (0..width)
                    .map(|x| terminal.backend().buffer()[(x, area.y)].symbol())
                    .collect::<String>();
                assert!(row.contains(labels[i]), "width {width}: {row}");
                let event = MouseEvent {
                    kind: MouseEventKind::Down(MouseButton::Left),
                    column: bounds[i].x,
                    row: area.y,
                    modifiers: KeyModifiers::NONE,
                };
                mouse(&mut app, event, screen);
                assert_eq!(app.input_source, SOURCES[i]);
            }
        }
    }

    #[test]
    fn empty_list_can_return_focus_to_the_sources() {
        let dir = tempfile::tempdir().unwrap();
        let mut app = App::new().unwrap();
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.focus_sources();
        key(&mut app, KeyCode::Down);
        assert_eq!(app.focus, Focus::Contents);
        assert_eq!(app.state.selected(), None);
        key(&mut app, KeyCode::Up);
        assert_eq!(app.focus, Focus::Sources);
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.focus, Focus::Filter);
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.focus, Focus::Contents);
    }

    #[test]
    fn redraws_the_whole_interface_after_single_or_batch_execution() {
        for (batch, failed) in [(false, false), (false, true), (true, false), (true, true)] {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("test.sh");
            std::fs::write(&path, "exit 0").unwrap();
            let entry = Entry {
                name: "test.sh".into(),
                url: Url::from_file_path(path).unwrap(),
                directory: false,
            };
            let mut app = App::new().unwrap();
            app.mode = Mode::Browsing;
            let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
            draw_app(&mut terminal, &mut app).unwrap();
            assert!(format!("{:?}", terminal.backend().buffer()).contains("MyEasyToolkit"));
            if batch {
                app.selected_scripts.push(entry.clone());
                app.start_batch();
            }
            let action = if batch {
                Action::RunBatch(entry)
            } else {
                Action::Run(entry)
            };
            app.action_with_runner(action, &mut |_, _, _, _| {
                if failed {
                    Err("échec".into())
                } else {
                    Ok(())
                }
            });
            assert!(app.screen_needs_redraw);
            // The real terminal's alternate screen is blank after the script returns.
            terminal.backend_mut().clear().unwrap();
            assert!(!format!("{:?}", terminal.backend().buffer()).contains("MyEasyToolkit"));
            draw_app(&mut terminal, &mut app).unwrap();
            assert!(format!("{:?}", terminal.backend().buffer()).contains("MyEasyToolkit"));
            assert!(!app.screen_needs_redraw);
        }
    }

    #[test]
    fn filter_and_descriptions_work_with_mouse_and_keyboard() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let dir = tempfile::tempdir().unwrap();
        for (name, contents) in [
            ("alpha.sh", "echo ok"),
            (
                "alpha.txt",
                "Résumé\nUne ligne\nDeux lignes\nTrois lignes\nQuatre lignes\nFin",
            ),
            ("windows.ps1", ""),
            (".htaccess", "private"),
            (".htpasswd", "private"),
            ("autre.md", ""),
        ] {
            std::fs::write(dir.path().join(name), contents).unwrap();
        }
        let mut app = App::new().unwrap();
        app.interpreters = Interpreters {
            bash: Some(PathBuf::from("bash")),
            powershell: None,
        };
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        assert_eq!(
            app.entries
                .iter()
                .map(|e| e.name.as_str())
                .collect::<Vec<_>>(),
            ["alpha.sh"]
        );
        for _ in 0..100 {
            app.update_descriptions();
            if app.description_text().starts_with("Résumé") {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(app.description_text().contains("Fin"));
        let screen = Rect::new(0, 0, 60, 24);
        let areas = UiAreas::new(screen);
        let mut terminal = Terminal::new(TestBackend::new(60, 24)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        key(&mut app, KeyCode::PageDown);
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        assert!(app.description_scroll > 0);
        let wheel = MouseEvent {
            kind: MouseEventKind::ScrollUp,
            column: areas.description.x + 1,
            row: areas.description.y + 1,
            modifiers: KeyModifiers::NONE,
        };
        mouse(&mut app, wheel, screen);
        assert_eq!(app.description_scroll, 0);
        let down_button = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: areas.description.x
                + 1
                + UnicodeWidthStr::width(" Description · Pg↑/Pg↓ · [↑] ") as u16,
            row: areas.description.y,
            modifiers: KeyModifiers::NONE,
        };
        mouse(&mut app, down_button, screen);
        assert_eq!(app.description_scroll, 3);
        let before = app.state.selected();
        mouse(&mut app, wheel, screen);
        assert_eq!(app.state.selected(), before);
        assert_eq!(app.description_scroll, 0);
        let click = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: areas.filter.x + 2,
            row: areas.filter.y,
            modifiers: KeyModifiers::NONE,
        };
        mouse(&mut app, click, screen);
        assert!(app.show_all);
        let names: Vec<_> = app.entries.iter().map(|e| e.name.as_str()).collect();
        assert!(
            names.contains(&"alpha.txt")
                && names.contains(&"windows.ps1")
                && names.contains(&"autre.md")
        );
        assert!(!names.contains(&".htaccess") && !names.contains(&".htpasswd"));
        key(&mut app, KeyCode::Char('t'));
        assert_eq!(app.entries.len(), 1);
    }

    #[test]
    fn description_wrap_is_bounded_and_preserves_all_text() {
        assert_eq!(wrap_description("abcde\nfin", 3), ["abc", "de", "fin"]);
        assert_eq!(wrap_description("界界", 2), ["界", "界"]);
        assert!(wrap_description("test", 0).is_empty());
    }

    #[test]
    fn long_locations_keep_the_end_and_fit_the_available_cells() {
        let path = "https://example.com/long/chemin/界/résultat.sh";
        for width in 0..=50 {
            let value = compact_location(path, width);
            assert!(UnicodeWidthStr::width(value.as_str()) <= width);
            if width >= 20 && UnicodeWidthStr::width(path) > width {
                assert!(value.ends_with("résultat.sh"));
                assert!(value.contains('…'));
            }
        }
        assert_eq!(compact_location("court", 5), "court");
    }

    #[test]
    fn selection_panel_adapts_to_width_and_displays_the_order() {
        let mut app = App::new().unwrap();
        app.mode = Mode::Browsing;
        for name in ["premier.sh", "second.sh"] {
            let entry = Entry {
                name: name.into(),
                url: Url::parse(&format!("https://example.com/{name}")).unwrap(),
                directory: false,
            };
            app.entries.push(entry.clone());
            app.selected_scripts.push(entry);
        }
        app.state.select(Some(0));
        let wide = UiAreas::new(Rect::new(0, 0, 110, 30));
        let narrow = UiAreas::new(Rect::new(0, 0, 60, 24));
        let panel = wide.selection.expect("wide terminal has a selection panel");
        assert!(wide.list.right() < panel.x);
        assert!(narrow.selection.is_none());
        let mut terminal = Terminal::new(TestBackend::new(110, 30)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        let buffer = terminal.backend().buffer();
        let row = |y| {
            (panel.x..panel.right())
                .map(|x| buffer[(x, y)].symbol())
                .collect::<String>()
        };
        assert!(row(panel.y + 1).contains("premier.sh"));
        assert!(row(panel.y + 2).contains("second.sh"));
        assert!(row(panel.y + 1).contains('1'));
        assert!(row(panel.y + 2).contains('2'));
        assert!(row(panel.bottom() - 4).contains("Élément actif"));
        assert!(row(panel.bottom() - 3).contains("premier.sh"));
    }

    #[test]
    fn compact_controls_remain_clickable() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let click = |x, y| MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: x,
            row: y,
            modifiers: KeyModifiers::NONE,
        };
        let screen = Rect::new(0, 0, 28, 18);
        let areas = UiAreas::new(screen);
        let mut app = App::new().unwrap();
        mouse(&mut app, click(12, areas.sources.y), screen);
        assert_eq!(app.input_source, Source::Http);
        mouse(&mut app, click(22, areas.sources.y), screen);
        assert_eq!(app.input_source, Source::Github);
        app.mode = Mode::Browsing;
        app.selected_scripts.push(Entry {
            name: "test.sh".into(),
            url: Url::parse("https://example.com/test.sh").unwrap(),
            directory: false,
        });
        mouse(&mut app, click(2, areas.batch_bar.y), screen);
        assert!(matches!(app.mode, Mode::ConfirmBatch));
        key(&mut app, KeyCode::Esc);
        mouse(&mut app, click(11, areas.batch_bar.y), screen);
        assert!(app.selected_scripts.is_empty());
        assert!(!mouse(&mut app, click(18, areas.footer.y), screen));
    }

    fn key(app: &mut App, code: KeyCode) {
        assert!(app.key(KeyEvent::new(code, KeyModifiers::NONE)));
    }

    #[test]
    fn confirmation_buttons_follow_keyboard_focus_and_cancel_safely() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.sh");
        std::fs::write(&path, "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.select();
        assert!(matches!(app.mode, Mode::Confirm(_)));
        assert_eq!(app.dialog_focus, 0);
        key(&mut app, KeyCode::Right);
        assert_eq!(app.dialog_focus, 1);
        assert!(matches!(app.mode, Mode::Confirm(_)));
        key(&mut app, KeyCode::Enter);
        assert!(matches!(app.mode, Mode::Browsing));
        assert!(app.batch.is_none());
    }

    #[test]
    fn keyboard_can_reach_batch_actions_toggle_and_confirm() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.focus_sources();
        key(&mut app, KeyCode::Down);
        key(&mut app, KeyCode::Char(' '));
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.focus, Focus::Controls);
        key(&mut app, KeyCode::Enter);
        assert!(matches!(app.mode, Mode::ConfirmBatch));
        key(&mut app, KeyCode::Right);
        key(&mut app, KeyCode::Enter);
        assert!(matches!(app.mode, Mode::Browsing));
        assert!(app.batch.is_none());
        key(&mut app, KeyCode::Enter);
        key(&mut app, KeyCode::Left);
        assert_eq!(app.dialog_focus, 2);
        key(&mut app, KeyCode::Char(' '));
        assert!(!app.stop_on_error);
        key(&mut app, KeyCode::Tab);
        key(&mut app, KeyCode::Enter);
        assert!(!app.batch.as_ref().unwrap().stop_on_error);
    }

    #[test]
    fn filter_is_reachable_without_shortcuts() {
        let mut app = App::new().unwrap();
        app.mode = Mode::Browsing;
        app.focus_sources();
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.focus, Focus::Filter);
        key(&mut app, KeyCode::Enter);
        assert!(app.show_all);
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.focus, Focus::Contents);
    }

    #[test]
    fn editing_current_remote_location_preserves_its_address() {
        let mut app = App::new().unwrap();
        let url = github_url("https://github.com/community-scripts/ProxmoxVE").unwrap();
        let expected = location_label(&url);
        app.current = Some(url);
        app.mode = Mode::Browsing;
        key(&mut app, KeyCode::Char('o'));
        assert!(matches!(app.mode, Mode::Url));
        assert_eq!(app.input_source, Source::Github);
        assert_eq!(app.input.text, expected);
    }

    #[test]
    fn url_field_and_buttons_are_reachable_with_tab() {
        let mut app = App::new().unwrap();
        app.select_source(Source::Http);
        app.input.insert("example.com/");
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.auth_focus, 1);
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.auth_focus, 2);
        key(&mut app, KeyCode::Up);
        assert_eq!(app.auth_focus, 0);
        let before = app.input.cursor;
        key(&mut app, KeyCode::Left);
        assert!(app.input.cursor < before);
    }

    #[test]
    fn connection_error_returns_focus_to_url_field() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 1024];
            let _ = stream.read(&mut request).unwrap();
            stream
                .write_all(
                    b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .unwrap();
        });
        let mut app = App::new().unwrap();
        app.select_source(Source::Http);
        app.input.clear();
        app.input.insert(&format!("http://{address}/missing/"));
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.auth_focus, 1);
        key(&mut app, KeyCode::Enter);
        server.join().unwrap();
        assert!(matches!(app.mode, Mode::Url));
        assert_eq!(app.auth_focus, 0);
        assert!(!app.message.is_empty());
    }

    #[test]
    fn credentials_support_keyboard_buttons_without_revealing_password() {
        let mut app = App::new().unwrap();
        let action = Action::Open(Url::parse("https://example.com/private/").unwrap());
        app.mode = Mode::Password(action, "user".into());
        app.input.insert("secret-test");
        key(&mut app, KeyCode::Tab);
        assert_eq!(app.auth_focus, 1);
        key(&mut app, KeyCode::Right);
        assert_eq!(app.auth_focus, 2);
        let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        let buffer = terminal.backend().buffer();
        assert!(!format!("{buffer:?}").contains("secret-test"));
        let popup = popup_area(Rect::new(0, 0, 80, 24));
        assert!(buffer[(popup.x + 16, popup.y + 4)]
            .modifier
            .contains(Modifier::REVERSED));
        key(&mut app, KeyCode::Enter);
        assert!(!matches!(app.mode, Mode::Password(_, _)));
        assert!(app.input.text.is_empty());
    }

    #[test]
    fn small_dialog_has_visible_and_clickable_buttons() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let mut app = App::new().unwrap();
        app.mode = Mode::Confirm(Entry {
            name: "test.sh".into(),
            url: Url::parse("https://example.com/test.sh").unwrap(),
            directory: false,
        });
        let area = Rect::new(0, 0, 24, 16);
        let popup = popup_area(area);
        let mut terminal = Terminal::new(TestBackend::new(area.width, area.height)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        let buffer = terminal.backend().buffer();
        assert!(format!("{buffer:?}").contains("[Oui] [Non]"));
        assert!(buffer[(popup.x + 2, popup.bottom() - 2)]
            .modifier
            .contains(Modifier::REVERSED));
        let click = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: popup.x + 8,
            row: popup.bottom() - 2,
            modifiers: KeyModifiers::NONE,
        };
        mouse(&mut app, click, area);
        assert!(matches!(app.mode, Mode::Browsing));
    }

    #[test]
    fn interface_inherits_terminal_colors_and_offers_icon_fallback() {
        use ratatui::style::Color;
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("folder")).unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        app.icons = true;
        let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        assert!(format!("{:?}", terminal.backend().buffer()).contains("📁"));
        for cell in &terminal.backend().buffer().content {
            assert_eq!(cell.fg, Color::Reset);
            assert_eq!(cell.bg, Color::Reset);
        }
        key(&mut app, KeyCode::Char('i'));
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        assert!(format!("{:?}", terminal.backend().buffer()).contains("[D]"));
        app.mode = Mode::Username(Action::Open(Url::parse("https://example.com/").unwrap()));
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        for cell in &terminal.backend().buffer().content {
            assert_eq!(cell.fg, Color::Reset);
            assert_eq!(cell.bg, Color::Reset);
        }
        let popup = popup_area(Rect::new(0, 0, 80, 24));
        assert!(terminal.backend().buffer()[(popup.x + 2, popup.y + 2)]
            .modifier
            .contains(Modifier::UNDERLINED));
    }

    #[test]
    fn ordered_selection_supports_mouse_keyboard_folders_and_renumbering() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        for name in ["a.sh", "b.sh", "other.txt"] {
            std::fs::write(dir.path().join(name), "").unwrap();
        }
        std::fs::write(dir.path().join("sub/c.ps1"), "").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        let screen = Rect::new(0, 0, 80, 24);
        let areas = UiAreas::new(screen);
        let click = |x, y| MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: x,
            row: y,
            modifiers: KeyModifiers::NONE,
        };
        // Listing puts the folder before the files. Select b first with the mouse, then a with space.
        mouse(&mut app, click(areas.list.x + 3, areas.list.y + 3), screen);
        app.state.select(Some(1));
        key(&mut app, KeyCode::Char(' '));
        assert_eq!(
            app.selected_scripts
                .iter()
                .map(|e| e.name.as_str())
                .collect::<Vec<_>>(),
            ["b.sh", "a.sh"]
        );
        key(&mut app, KeyCode::Char(' '));
        key(&mut app, KeyCode::Char(' '));
        assert_eq!(
            app.selected_scripts
                .iter()
                .map(|e| e.name.as_str())
                .collect::<Vec<_>>(),
            ["b.sh", "a.sh"]
        );
        app.state.select(Some(0));
        key(&mut app, KeyCode::Enter);
        if app.interpreters.powershell.is_none() {
            key(&mut app, KeyCode::Char('t'));
        }
        key(&mut app, KeyCode::Char(' '));
        assert_eq!(
            app.selected_scripts
                .iter()
                .map(|e| e.name.as_str())
                .collect::<Vec<_>>(),
            ["b.sh", "a.sh", "c.ps1"]
        );
        app.parent();
        let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| draw(frame, &mut app)).unwrap();
        let content = format!("{:?}", terminal.backend().buffer());
        assert!(content.contains("[ 1]"));
        assert!(content.contains("[ 2]"));
        mouse(
            &mut app,
            click(areas.batch_bar.x + 2, areas.batch_bar.y),
            screen,
        );
        assert!(matches!(app.mode, Mode::ConfirmBatch));
        let popup = batch_popup_area(screen);
        mouse(&mut app, click(popup.x + 3, popup.bottom() - 4), screen);
        assert!(!app.stop_on_error);
        mouse(&mut app, click(popup.x + 14, popup.bottom() - 2), screen);
        assert!(matches!(app.mode, Mode::Browsing));
        assert!(app.batch.is_none());
        mouse(
            &mut app,
            click(areas.batch_bar.x + 2, areas.batch_bar.y),
            screen,
        );
        mouse(&mut app, click(popup.x + 3, popup.bottom() - 2), screen);
        assert!(app.batch.is_some());
        assert!(!app.batch.as_ref().unwrap().stop_on_error);
        app.batch = None;
        mouse(
            &mut app,
            click(areas.batch_bar.x + 13, areas.batch_bar.y),
            screen,
        );
        assert!(app.selected_scripts.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn batch_executes_in_order_and_respects_nonzero_exit_and_launch_errors() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("order");
        let mut entries = Vec::new();
        for (name, body) in [
            ("first.sh", "printf A; exit 7"),
            ("second.sh", "printf B; exit 0"),
            ("third.sh", "printf C; exit 0"),
        ] {
            let path = dir.path().join(name);
            std::fs::write(&path, format!("{{ {body}; }} >> '{}'", log.display())).unwrap();
            entries.push(Entry {
                name: name.into(),
                url: Url::from_file_path(path).unwrap(),
                directory: false,
            });
        }
        for (stop, expected) in [(true, "A"), (false, "ABC")] {
            let _ = std::fs::remove_file(&log);
            let mut app = App::new().unwrap();
            app.selected_scripts = entries.clone();
            app.stop_on_error = stop;
            app.start_batch();
            while app.batch.is_some() {
                app.advance_batch_with(&mut |entry, data, _, _| execute_script(entry, data));
            }
            assert_eq!(std::fs::read_to_string(&log).unwrap(), expected);
            assert!(app.message.contains("1 échec(s)"));
            assert!(matches!(app.mode, Mode::Message));
        }
        std::fs::remove_file(dir.path().join("first.sh")).unwrap();
        let mut app = App::new().unwrap();
        app.selected_scripts = entries;
        app.start_batch();
        app.advance_batch_with(&mut |entry, data, _, _| execute_script(entry, data));
        assert!(app.batch.is_none());
        assert!(app.message.contains("2 script(s) non lancé(s)"));
    }

    #[test]
    fn batch_pauses_for_authentication_and_resumes_same_script() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = Url::parse(&format!(
            "http://{}/private/test.sh",
            listener.local_addr().unwrap()
        ))
        .unwrap();
        let server = thread::spawn(move || {
            for i in 0..2 {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0; 2048];
                let len = stream.read(&mut request).unwrap();
                if i == 1 {
                    assert!(String::from_utf8_lossy(&request[..len])
                        .to_ascii_lowercase()
                        .contains("authorization: basic "));
                }
                let response = if i == 0 {
                    "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                } else {
                    "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nexit 0"
                };
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        let entry = Entry {
            name: "test.sh".into(),
            url: url.clone(),
            directory: false,
        };
        let mut app = App::new().unwrap();
        app.selected_scripts.push(entry.clone());
        app.start_batch();
        app.advance_batch_with(&mut |_, _, _, _| panic!("must not execute before authentication"));
        assert!(matches!(app.mode, Mode::Username(Action::RunBatch(_))));
        assert_eq!(app.batch.as_ref().unwrap().next, 0);
        app.repo
            .authenticate(url.join("./").unwrap(), "user".into(), "pass".into());
        let mut called = false;
        app.action_with_runner(Action::RunBatch(entry), &mut |_, data, wait, _| {
            called = true;
            assert_eq!(data, b"exit 0");
            assert!(wait);
            Ok(())
        });
        server.join().unwrap();
        assert!(called);
        assert!(app.batch.is_none());
        assert!(app.message.contains("0 échec(s)"));
    }

    #[test]
    fn canceling_authentication_stops_batch_but_keeps_selection() {
        let entry = Entry {
            name: "test.sh".into(),
            url: Url::parse("https://example.com/private/test.sh").unwrap(),
            directory: false,
        };
        let mut app = App::new().unwrap();
        app.selected_scripts.push(entry.clone());
        app.start_batch();
        app.mode = Mode::Username(Action::RunBatch(entry));
        key(&mut app, KeyCode::Esc);
        assert!(app.batch.is_none());
        assert_eq!(app.selected_scripts.len(), 1);
        assert!(matches!(app.mode, Mode::Message));
    }

    #[test]
    fn download_failure_obeys_the_batch_error_policy() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        for stop in [true, false] {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let remote = Url::parse(&format!(
                "http://{}/missing.sh",
                listener.local_addr().unwrap()
            ))
            .unwrap();
            let server = thread::spawn(move || {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0; 1024];
                let _ = stream.read(&mut request).unwrap();
                stream
                    .write_all(
                        b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    )
                    .unwrap();
            });
            let local = tempfile::tempdir().unwrap();
            let mut app = App::new().unwrap();
            app.selected_scripts = vec![
                Entry {
                    name: "missing.sh".into(),
                    url: remote,
                    directory: false,
                },
                Entry {
                    name: "next.sh".into(),
                    url: Url::from_file_path(local.path().join("next.sh")).unwrap(),
                    directory: false,
                },
            ];
            app.stop_on_error = stop;
            app.start_batch();
            let mut runs = 0;
            while app.batch.is_some() {
                app.advance_batch_with(&mut |_, _, _, _| {
                    runs += 1;
                    Ok(())
                });
            }
            server.join().unwrap();
            assert_eq!(runs, usize::from(!stop));
            assert!(app.message.contains("1 échec(s)"));
        }
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
        let (_, _, _, sources) = source_layout(areas.sources);
        mouse(&mut app, click(sources[1].x, areas.sources.y), screen);
        assert!(matches!(app.mode, Mode::Url));
        assert_eq!(app.input.text, "https://");
        mouse(&mut app, click(5, areas.location.y + 1), screen);
        assert_eq!(app.input.cursor, 4);
        app.key(KeyEvent::new(KeyCode::Delete, KeyModifiers::NONE));
        assert_eq!(app.input.text, "http://");
        mouse(&mut app, click(sources[2].x, areas.sources.y), screen);
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
    fn mouse_can_open_a_source_go_back_submit_an_address_and_quit() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let click = |x, y| MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: x,
            row: y,
            modifiers: KeyModifiers::NONE,
        };
        let screen = Rect::new(0, 0, 80, 24);
        let areas = UiAreas::new(screen);
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("child")).unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
        app.action(Action::OpenRoot(
            Url::from_directory_path(dir.path()).unwrap(),
        ));
        assert!(mouse(&mut app, click(3, areas.list.y + 1), screen));
        assert!(mouse(&mut app, click(2, areas.footer.y), screen));
        assert_eq!(
            app.current.as_ref().unwrap().to_file_path().unwrap(),
            dir.path()
        );
        let (_, _, _, sources) = source_layout(areas.sources);
        assert!(mouse(
            &mut app,
            click(sources[1].x, areas.sources.y),
            screen
        ));
        assert_eq!(app.input.text, "https://");
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0; 2048];
            let _ = stream.read(&mut request);
            let body = "<a href=\"script.sh\">script.sh</a>";
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            )
            .unwrap();
        });
        app.input.clear();
        app.input.insert(&format!("http://{address}/"));
        assert!(mouse(&mut app, click(2, areas.footer.y), screen));
        server.join().unwrap();
        assert!(matches!(app.mode, Mode::Browsing));
        assert_eq!(app.entries[0].name, "script.sh");
        assert!(!mouse(&mut app, click(26, areas.footer.y), screen));
    }

    #[test]
    fn selecting_a_script_requires_confirmation_and_mouse_can_cancel() {
        use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("test.sh"), "exit 0").unwrap();
        let mut app = App::new().unwrap();
        app.interpreters.bash = Some(PathBuf::from("bash"));
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

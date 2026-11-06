use crate::repository::{Entry, Repository};
use std::{
    collections::VecDeque,
    sync::{mpsc, Arc},
    thread,
};
use url::Url;

pub const LIMIT: usize = 32 * 1024;

// Match actual URL paths as well as labels: HTML index labels are untrusted.
pub fn leaf(entry: &Entry) -> String {
    let segment = entry
        .url
        .path()
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or("");
    let bytes = segment.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(a), Some(b)) = (
                (bytes[i + 1] as char).to_digit(16),
                (bytes[i + 2] as char).to_digit(16),
            ) {
                decoded.push((a * 16 + b) as u8);
                i += 3;
                continue;
            }
        }
        decoded.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

pub fn protected(entry: &Entry) -> bool {
    [&entry.name, &leaf(entry)].iter().any(|name| {
        let name = name.trim_end_matches('/');
        name.eq_ignore_ascii_case(".htaccess") || name.eq_ignore_ascii_case(".htpasswd")
    })
}

pub fn sidecar<'a>(script: &Entry, entries: &'a [Entry]) -> Option<&'a Entry> {
    let file = leaf(script);
    if script.directory
        || !(file.to_ascii_lowercase().ends_with(".sh")
            || file.to_ascii_lowercase().ends_with(".ps1"))
    {
        return None;
    }
    let (stem, _) = file.rsplit_once('.')?;
    let target = format!("{stem}.txt");
    entries
        .iter()
        .find(|entry| !entry.directory && !protected(entry) && leaf(entry) == target)
}

pub fn clean(bytes: &[u8]) -> Result<String, &'static str> {
    if bytes.len() > LIMIT {
        return Err("Description trop volumineuse (32 Kio maximum).");
    }
    let text =
        std::str::from_utf8(bytes).map_err(|_| "Description illisible : texte UTF-8 attendu.")?;
    let mut output = String::new();
    let mut chars = text.trim_start_matches('\u{feff}').chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            if chars.peek() == Some(&'[') {
                chars.next();
                for next in chars.by_ref() {
                    if ('@'..='~').contains(&next) {
                        break;
                    }
                }
            }
            continue;
        }
        if c == '\r' {
            continue;
        }
        if c == '\n' || c == '\t' {
            output.push(if c == '\t' { ' ' } else { c });
        } else if !c.is_control() && !matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        {
            output.push(c);
        }
    }
    Ok(output.trim().to_string())
}

pub enum Request {
    Replace(u64, Arc<Repository>, Vec<Url>),
    Prioritize(u64, Url),
}
pub struct Loader {
    pub requests: mpsc::Sender<Request>,
    pub results: mpsc::Receiver<(u64, Url, Result<String, String>)>,
}
impl Loader {
    pub fn new() -> Self {
        let (send, receive) = mpsc::channel::<Request>();
        let (results, output) = mpsc::channel();
        thread::spawn(move || {
            let mut generation = 0;
            let mut repo: Option<Arc<Repository>> = None;
            let mut queue = VecDeque::new();
            loop {
                let request = if queue.is_empty() {
                    match receive.recv() {
                        Ok(r) => Some(r),
                        Err(_) => break,
                    }
                } else {
                    receive.try_recv().ok()
                };
                if let Some(request) = request {
                    match request {
                        Request::Replace(new_generation, new_repo, urls) => {
                            generation = new_generation;
                            repo = Some(new_repo);
                            queue = urls.into();
                        }
                        Request::Prioritize(g, url) if g == generation => {
                            if let Some(i) = queue.iter().position(|item| *item == url) {
                                if let Some(item) = queue.remove(i) {
                                    queue.push_front(item);
                                }
                            }
                        }
                        Request::Prioritize(_, _) => {}
                    }
                    continue;
                }
                let Some(url) = queue.pop_front() else {
                    continue;
                };
                let Some(repo) = &repo else { continue };
                let result = repo
                    .fetch_description(&url)
                    .map_err(|_| "Description indisponible ou trop volumineuse.".to_string())
                    .and_then(|bytes| clean(&bytes).map_err(str::to_string));
                if results.send((generation, url, result)).is_err() {
                    break;
                }
            }
        });
        Self {
            requests: send,
            results: output,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(name: &str, path: &str) -> Entry {
        Entry {
            name: name.into(),
            url: Url::parse(&format!("https://example.com/{path}")).unwrap(),
            directory: false,
        }
    }
    #[test]
    fn sidecars_use_actual_filename_and_block_sensitive_names() {
        let script = entry("Backup", "backup.sh");
        let entries = vec![
            entry("description", "backup.txt"),
            entry("innocent", "%2Ehtaccess"),
            entry(".htpasswd", "other"),
        ];
        assert_eq!(sidecar(&script, &entries).unwrap().url, entries[0].url);
        assert!(protected(&entries[1]));
        assert!(protected(&entries[2]));
        assert!(sidecar(&entry("no", "other.sh"), &entries).is_none());
    }
    #[test]
    fn descriptions_are_limited_utf8_and_cannot_emit_terminal_controls() {
        assert_eq!(
            clean(b"\xef\xbb\xbfSalut\x1b[31m rouge\x1b[0m\r\nligne\tfin\x07").unwrap(),
            "Salut rouge\nligne fin"
        );
        assert!(clean(&[0xff]).is_err());
        assert!(clean(&vec![b'a'; LIMIT + 1]).is_err());
        assert_eq!(clean("un\u{202e}deux".as_bytes()).unwrap(), "undeux");
    }
}

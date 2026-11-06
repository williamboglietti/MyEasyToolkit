use reqwest::{blocking::Client, redirect::Policy, StatusCode};
use scraper::{Html, Selector};
use std::{io::Read, time::Duration};
use url::Url;

const MAX_BYTES: u64 = 4 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub url: Url,
    pub directory: bool,
}

#[derive(Clone)]
pub struct Credentials {
    pub scope: Url,
    pub username: String,
    pub password: String,
}

pub enum FetchError {
    Unauthorized,
    Message(String),
}

pub fn normalize_url(input: &str) -> Result<Url, String> {
    let input = input.trim();
    let text = if input.contains("://") {
        input.to_owned()
    } else {
        format!("https://{input}")
    };
    let mut url = Url::parse(&text).map_err(|e| format!("URL invalide : {e}"))?;
    if !matches!(url.scheme(), "http" | "https")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err("Utilisez une URL HTTP(S) sans identifiants intégrés.".into());
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err("L’URL du dépôt ne doit pas contenir de paramètres ni de fragment.".into());
    }
    if !url.path().ends_with('/') {
        url.set_path(&format!("{}/", url.path()));
    }
    Ok(url)
}

/// Convert a public GitHub repository URL into its contents API root.
pub fn github_url(input: &str) -> Result<Url, String> {
    let url = normalize_url(input)?;
    if url.scheme() != "https" || url.host_str() != Some("github.com") {
        return Err("Saisissez une adresse HTTPS de dépôt GitHub public.".into());
    }
    let parts: Vec<_> = url
        .path_segments()
        .into_iter()
        .flatten()
        .filter(|s| !s.is_empty())
        .collect();
    if parts.len() != 2 || parts[0].is_empty() || parts[1].trim_end_matches(".git").is_empty() {
        return Err(
            "Utilisez l’adresse d’un dépôt, par exemple https://github.com/proprietaire/depot"
                .into(),
        );
    }
    let mut api = Url::parse("https://api.github.com/repos/").expect("constant URL");
    api.path_segments_mut()
        .expect("API base URL")
        .pop_if_empty()
        .push(parts[0])
        .push(parts[1].trim_end_matches(".git"))
        .push("contents")
        .push("");
    Ok(api)
}

pub fn is_github_api(url: &Url) -> bool {
    url.scheme() == "https"
        && url.host_str() == Some("api.github.com")
        && url.path().starts_with("/repos/")
        && url.path().contains("/contents/")
}

fn github_request_url(url: &Url) -> Url {
    // Directory API URLs redirect if they end in a slash; keep redirects disabled.
    let mut request_url = url.clone();
    if is_github_api(url)
        && url
            .path()
            .split_once("/contents/")
            .is_some_and(|(_, path)| !path.is_empty())
        && url.path().ends_with('/')
    {
        request_url
            .path_segments_mut()
            .expect("GitHub URL has path segments")
            .pop_if_empty();
    }
    request_url
}

pub fn parse_github_listing(base: &Url, bytes: &[u8]) -> Result<Vec<Entry>, String> {
    let data: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| "Réponse GitHub illisible.".to_string())?;
    let items = data
        .as_array()
        .ok_or_else(|| "GitHub n’a pas renvoyé une liste de fichiers.".to_string())?;
    if items.len() >= 1000 {
        return Err("GitHub limite les listes à 1 000 éléments : ce dossier est trop volumineux pour être affiché intégralement.".into());
    }
    let mut entries = Vec::new();
    for item in items {
        let Some(name) = item.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let directory = match item.get("type").and_then(|v| v.as_str()) {
            Some("dir") => true,
            Some("file") if item.get("submodule_git_url").is_none_or(|v| v.is_null()) => false,
            _ => continue,
        };
        let mut url = base.clone();
        url.path_segments_mut()
            .map_err(|_| "Adresse GitHub invalide.".to_string())?
            .pop_if_empty()
            .push(name);
        if directory {
            url.path_segments_mut()
                .map_err(|_| "Adresse GitHub invalide.".to_string())?
                .push("");
        }
        entries.push(Entry {
            name: name.to_owned(),
            url,
            directory,
        });
    }
    sort_entries(&mut entries);
    Ok(entries)
}

pub fn local_listing(url: &Url) -> Result<Vec<Entry>, String> {
    let path = url
        .to_file_path()
        .map_err(|_| "Chemin local invalide.".to_string())?;
    let mut entries = Vec::new();
    for item in
        std::fs::read_dir(&path).map_err(|e| format!("Lecture du dossier impossible : {e}"))?
    {
        let item = item.map_err(|e| format!("Lecture du dossier impossible : {e}"))?;
        let kind = item
            .file_type()
            .map_err(|e| format!("Lecture du fichier impossible : {e}"))?;
        // Do not follow symlinks out of the chosen root.
        if !kind.is_dir() && !kind.is_file() {
            continue;
        }
        let url = if kind.is_dir() {
            Url::from_directory_path(item.path())
        } else {
            Url::from_file_path(item.path())
        }
        .map_err(|_| "Chemin local invalide.".to_string())?;
        entries.push(Entry {
            name: item.file_name().to_string_lossy().into_owned(),
            url,
            directory: kind.is_dir(),
        });
    }
    sort_entries(&mut entries);
    Ok(entries)
}

fn sort_entries(entries: &mut [Entry]) {
    entries.sort_by(|a, b| {
        b.directory
            .cmp(&a.directory)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
}

fn same_origin(a: &Url, b: &Url) -> bool {
    a.origin() == b.origin()
}

pub fn parse_listing(base: &Url, html: &str) -> Vec<Entry> {
    let document = Html::parse_document(html);
    let selector = Selector::parse("a[href]").expect("valid selector");
    let mut result: Vec<Entry> = Vec::new();
    for link in document.select(&selector) {
        let href = link.value().attr("href").unwrap_or_default();
        if href.starts_with('?') || href.starts_with('#') {
            continue;
        }
        let Ok(mut url) = base.join(href) else {
            continue;
        };
        if !same_origin(base, &url)
            || url.query().is_some()
            || url.fragment().is_some()
            || !url.username().is_empty()
        {
            continue;
        }
        let Some(tail) = url.path().strip_prefix(base.path()) else {
            continue;
        };
        let directory = tail.ends_with('/');
        let leaf = tail.trim_end_matches('/');
        if leaf.is_empty() || leaf.contains('/') || leaf.eq_ignore_ascii_case("%2e%2e") {
            continue;
        }
        let name = link.text().collect::<String>().trim().to_owned();
        if name.is_empty() || name == "Parent Directory" {
            continue;
        }
        url.set_fragment(None);
        if !result.iter().any(|entry| entry.url == url) {
            result.push(Entry {
                name,
                url,
                directory,
            });
        }
    }
    sort_entries(&mut result);
    result
}

pub struct Repository {
    client: Client,
    credentials: Vec<Credentials>,
}
impl Repository {
    pub fn new() -> Result<Self, String> {
        let client = Client::builder()
            .timeout(Duration::from_secs(20))
            .redirect(Policy::none())
            .user_agent(concat!("MyEasyToolkit/", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(|e| e.to_string())?;
        Ok(Self {
            client,
            credentials: Vec::new(),
        })
    }
    pub fn authenticate(&mut self, scope: Url, username: String, password: String) {
        self.credentials.retain(|c| c.scope != scope);
        self.credentials.push(Credentials {
            scope,
            username,
            password,
        });
    }
    pub fn fetch(&self, url: &Url) -> Result<Vec<u8>, FetchError> {
        self.fetch_with_accept(url, None)
    }
    pub fn fetch_github_script(&self, url: &Url) -> Result<Vec<u8>, FetchError> {
        self.fetch_with_accept(url, Some("application/vnd.github.raw+json"))
    }
    fn fetch_with_accept(&self, url: &Url, accept: Option<&str>) -> Result<Vec<u8>, FetchError> {
        let auth = self
            .credentials
            .iter()
            .filter(|c| same_origin(&c.scope, url) && url.path().starts_with(c.scope.path()))
            .max_by_key(|c| c.scope.path().len());
        if auth.is_some()
            && url.scheme() != "https"
            && !matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "::1"))
        {
            return Err(FetchError::Message(
                "L’authentification Basic exige HTTPS.".into(),
            ));
        }
        let mut request = self.client.get(github_request_url(url));
        if let Some(accept) = accept {
            request = request.header("Accept", accept);
        }
        if let Some(c) = auth {
            request = request.basic_auth(&c.username, Some(&c.password));
        }
        let response = request.send().map_err(|e| {
            FetchError::Message(format!("Connexion impossible : {}", e.without_url()))
        })?;
        if response.status() == StatusCode::UNAUTHORIZED {
            return Err(FetchError::Unauthorized);
        }
        if !response.status().is_success() {
            return Err(FetchError::Message(format!(
                "Le serveur a répondu : {}",
                response.status()
            )));
        }
        if response.content_length().is_some_and(|n| n > MAX_BYTES) {
            return Err(FetchError::Message(
                "Fichier trop volumineux (4 Mio maximum).".into(),
            ));
        }
        let mut data = Vec::new();
        response
            .take(MAX_BYTES + 1)
            .read_to_end(&mut data)
            .map_err(|e| FetchError::Message(format!("Lecture impossible : {e}")))?;
        if data.len() as u64 > MAX_BYTES {
            return Err(FetchError::Message(
                "Fichier trop volumineux (4 Mio maximum).".into(),
            ));
        }
        Ok(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn github_repository_and_children_are_constrained_to_the_contents_api() {
        let root = github_url("https://github.com/community-scripts/ProxmoxVE").unwrap();
        assert_eq!(
            root.as_str(),
            "https://api.github.com/repos/community-scripts/ProxmoxVE/contents/"
        );
        assert!(github_url("http://github.com/community-scripts/ProxmoxVE").is_err());
        assert!(github_url("https://github.com/community-scripts/ProxmoxVE/tree/main").is_err());
        let data = br#"[{"name":"z.sh","type":"file"},{"name":"ct","type":"dir"},{"name":"link","type":"symlink"}]"#;
        let entries = parse_github_listing(&root, data).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(
            entries[0].url.as_str(),
            "https://api.github.com/repos/community-scripts/ProxmoxVE/contents/ct/"
        );
        assert_eq!(github_request_url(&root), root);
        assert_eq!(
            github_request_url(&entries[0].url).as_str(),
            "https://api.github.com/repos/community-scripts/ProxmoxVE/contents/ct"
        );
        assert_eq!(github_request_url(&entries[1].url), entries[1].url);
        assert_eq!(
            entries[1].url.as_str(),
            "https://api.github.com/repos/community-scripts/ProxmoxVE/contents/z.sh"
        );
    }

    #[test]
    fn local_listing_uses_real_directories_and_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        std::fs::write(dir.path().join("test.sh"), "echo ok").unwrap();
        let root = Url::from_directory_path(dir.path()).unwrap();
        let entries = local_listing(&root).unwrap();
        assert_eq!(
            entries.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
            ["sub", "test.sh"]
        );
        assert!(entries[0].directory);
        assert_eq!(
            entries[1].url.to_file_path().unwrap(),
            dir.path().join("test.sh")
        );
    }

    #[test]
    fn apache_listing_only_immediate_same_origin_children() {
        let base = normalize_url("https://example.com/root/").unwrap();
        let html = r#"<a href="?C=N;O=D">Name</a><a href="/">Parent Directory</a><a href="private/">private/</a><a href="install.sh">install.sh</a><a href="https://evil.example/x">bad</a><a href="deep/file">deep</a><a href="/root/file?q=1">sort</a>"#;
        let entries = parse_listing(&base, html);
        assert_eq!(
            entries.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
            ["private/", "install.sh"]
        );
    }
    #[test]
    fn urls_are_normalized_and_credentials_rejected() {
        assert_eq!(
            normalize_url("exemple.invalid").unwrap().as_str(),
            "https://exemple.invalid/"
        );
        assert!(normalize_url("https://user:pass@example.com/").is_err());
        assert!(normalize_url("https://example.com/?sort=1").is_err());
    }
    #[test]
    fn basic_credentials_stay_in_the_protected_subtree() {
        use std::{
            io::{BufRead, BufReader, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let mut received = Vec::new();
            for _ in 0..3 {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = String::new();
                {
                    let mut reader = BufReader::new(&mut stream);
                    loop {
                        let mut line = String::new();
                        reader.read_line(&mut line).unwrap();
                        if line == "\r\n" || line.is_empty() {
                            break;
                        }
                        request.push_str(&line);
                    }
                }
                let first = received.is_empty();
                received.push(request);
                let status = if first { "401 Unauthorized" } else { "200 OK" };
                write!(
                    stream,
                    "HTTP/1.1 {status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                )
                .unwrap();
            }
            received
        });
        let root = Url::parse(&format!("http://{address}/")).unwrap();
        let private = root.join("private/").unwrap();
        let mut repo = Repository::new().unwrap();
        assert!(matches!(
            repo.fetch(&private),
            Err(FetchError::Unauthorized)
        ));
        repo.authenticate(private.clone(), "user".into(), "secret".into());
        assert!(repo.fetch(&private.join("script.sh").unwrap()).is_ok());
        assert!(repo.fetch(&root.join("public/").unwrap()).is_ok());
        let received = server.join().unwrap();
        assert!(!received[0].to_ascii_lowercase().contains("authorization:"));
        assert!(received[1]
            .to_ascii_lowercase()
            .contains("authorization: basic "));
        assert!(!received[2].to_ascii_lowercase().contains("authorization:"));
    }

    #[test]
    fn refuses_basic_credentials_over_plain_http() {
        let url = Url::parse("http://example.com/private/").unwrap();
        let mut repo = Repository::new().unwrap();
        repo.authenticate(url.clone(), "user".into(), "secret".into());
        assert!(matches!(repo.fetch(&url), Err(FetchError::Message(_))));
    }
}

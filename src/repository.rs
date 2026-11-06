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
    result.sort_by(|a, b| {
        b.directory
            .cmp(&a.directory)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
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
        let mut request = self.client.get(url.clone());
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
            normalize_url("mystorage.ovh").unwrap().as_str(),
            "https://mystorage.ovh/"
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

//! Prototype hors production : vérification d'un manifeste OpenPGP et d'un fichier.
use anyhow::{bail, ensure, Context, Result};
use openpgp::parse::{
    stream::{DetachedVerifierBuilder, MessageLayer, MessageStructure, VerificationHelper},
    Parse,
};
use openpgp::policy::StandardPolicy;
use openpgp::types::RevocationStatus;
use openpgp::{Cert, KeyHandle};
use sequoia_openpgp as openpgp;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::io::Read;

#[derive(Deserialize, Debug)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub version: String,
    pub platform: String,
    pub filename: String,
    pub size: u64,
    pub sha256: String,
    pub expires_unix: u64,
}

struct TrustedSigner {
    cert: Cert,
    fingerprint: String,
}

impl VerificationHelper for TrustedSigner {
    fn get_certs(&mut self, _ids: &[KeyHandle]) -> openpgp::Result<Vec<Cert>> {
        Ok(vec![self.cert.clone()])
    }

    fn check(&mut self, structure: MessageStructure) -> openpgp::Result<()> {
        let mut count = 0;
        for layer in structure.iter() {
            match layer {
                MessageLayer::SignatureGroup { results } => {
                    for result in results {
                        let good = result
                            .as_ref()
                            .map_err(|e| anyhow::anyhow!("Signature non valide : {e}"))?;
                        ensure!(
                            good.ka.key().fingerprint().to_string() == self.fingerprint,
                            "Signataire non autorisé"
                        );
                        count += 1;
                    }
                }
                _ => bail!("Structure de signature inattendue"),
            }
        }
        ensure!(count == 1, "Une seule signature valide est attendue");
        Ok(())
    }
}

/// Vérifie des octets déjà téléchargés ; n'installe ni ne lance le fichier.
pub fn verify_signature(key: &[u8], signer: &str, data: &[u8], signature: &[u8]) -> Result<()> {
    ensure!(signature.len() <= 32_768, "Signature trop volumineuse");
    let cert = Cert::from_bytes(key).context("Certificat OpenPGP invalide")?;
    let policy = StandardPolicy::new();
    let valid = cert
        .with_policy(&policy, None)
        .context("Certificat non valide actuellement")?;
    valid.alive().context("Certificat expiré")?;
    ensure!(
        !matches!(valid.revocation_status(), RevocationStatus::Revoked(_)),
        "Certificat révoqué"
    );
    ensure!(
        cert.keys()
            .with_policy(&policy, None)
            .alive()
            .revoked(false)
            .for_signing()
            .any(|key| key.key().fingerprint().to_string() == signer),
        "Clé de signature absente, expirée ou révoquée"
    );
    let helper = TrustedSigner {
        cert,
        fingerprint: signer.to_owned(),
    };
    DetachedVerifierBuilder::from_bytes(signature)?
        .with_policy(&policy, None, helper)?
        .verify_bytes(data)
        .context("Signature invalide")?;
    Ok(())
}

pub fn verify<R: Read>(
    key: &[u8],
    signer: &str,
    manifest_bytes: &[u8],
    signature: &[u8],
    mut artifact: R,
    platform: &str,
    now: u64,
) -> Result<Manifest> {
    ensure!(
        manifest_bytes.len() <= 32_768,
        "Métadonnées trop volumineuses"
    );
    verify_signature(key, signer, manifest_bytes, signature)
        .context("Signature du manifeste invalide")?;
    let manifest: Manifest =
        serde_json::from_slice(manifest_bytes).context("Manifeste invalide")?;
    ensure!(manifest.platform == platform, "Plateforme incorrecte");
    let expected_name = match platform {
        "darwin-arm64" => "myeasytoolkit-darwin-arm64.tar.gz",
        "darwin-amd64" => "myeasytoolkit-darwin-amd64.tar.gz",
        "windows-arm64" => "myeasytoolkit-windows-arm64.exe",
        "windows-amd64" => "myeasytoolkit-windows-amd64.exe",
        _ => bail!("Plateforme non prise en charge"),
    };
    ensure!(
        manifest.filename == expected_name,
        "Nom de fichier incorrect"
    );
    ensure!(manifest.expires_unix > now, "Manifeste expiré");
    ensure!(
        !manifest.version.is_empty() && manifest.version.len() <= 64,
        "Version invalide"
    );
    ensure!(
        manifest.size > 0 && manifest.size <= 100 * 1024 * 1024,
        "Taille invalide"
    );
    ensure!(
        manifest.sha256.len() == 64 && manifest.sha256.bytes().all(|b| b.is_ascii_hexdigit()),
        "Empreinte invalide"
    );
    let mut hasher = Sha256::new();
    let mut total = 0u64;
    let mut buffer = [0u8; 8192];
    loop {
        let count = artifact.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        total += count as u64;
        ensure!(total <= manifest.size, "Fichier plus grand qu'annoncé");
        hasher.update(&buffer[..count]);
    }
    ensure!(total == manifest.size, "Taille du fichier incorrecte");
    ensure!(
        hex::encode(hasher.finalize()).eq_ignore_ascii_case(&manifest.sha256),
        "Empreinte du fichier incorrecte"
    );
    Ok(manifest)
}

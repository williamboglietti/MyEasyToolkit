//! Simulation isolée d'une politique de retour arrière ; aucune installation réelle.
use crate::verify_signature;
use anyhow::{bail, ensure, Context, Result};
use semver::Version;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{cmp::Ordering, collections::HashSet, io::Read};

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Target {
    version: Version,
    filename: String,
    size: u64,
    sha256: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Catalog {
    schema: u32,
    metadata_version: u64,
    expires_unix: u64,
    platform: String,
    recommended: Version,
    targets: Vec<Target>,
}

/// Ne peut être créé qu'après vérification de la signature et des métadonnées.
pub struct VerifiedCatalog {
    catalog: Catalog,
    digest: String,
}

pub fn verify_catalog(
    key: &[u8],
    signer: &str,
    bytes: &[u8],
    signature: &[u8],
    platform: &str,
    now: u64,
) -> Result<VerifiedCatalog> {
    ensure!(bytes.len() <= 32_768, "Catalogue trop volumineux");
    verify_signature(key, signer, bytes, signature)?;
    let catalog: Catalog = serde_json::from_slice(bytes).context("Catalogue invalide")?;
    ensure!(
        catalog.schema == 1 && catalog.metadata_version > 0,
        "Format ou version de catalogue invalide"
    );
    ensure!(catalog.expires_unix > now, "Catalogue expiré");
    ensure!(catalog.platform == platform, "Plateforme incorrecte");
    let expected_name = match platform {
        "darwin-arm64" => "myeasytoolkit-darwin-arm64.tar.gz",
        "darwin-amd64" => "myeasytoolkit-darwin-amd64.tar.gz",
        "windows-arm64" => "myeasytoolkit-windows-arm64.exe",
        "windows-amd64" => "myeasytoolkit-windows-amd64.exe",
        _ => bail!("Plateforme non prise en charge"),
    };
    ensure!(
        !catalog.targets.is_empty() && catalog.targets.len() <= 100,
        "Nombre de versions invalide"
    );
    let mut versions = HashSet::new();
    for target in &catalog.targets {
        ensure!(
            target.version.build.is_empty(),
            "Métadonnées de version non prises en charge"
        );
        ensure!(
            versions.insert(target.version.clone()),
            "Version présente plusieurs fois"
        );
        ensure!(target.filename == expected_name, "Nom de fichier incorrect");
        ensure!(
            target.size > 0 && target.size <= 100 * 1024 * 1024,
            "Taille invalide"
        );
        ensure!(
            target.sha256.len() == 64 && target.sha256.bytes().all(|b| b.is_ascii_hexdigit()),
            "Empreinte invalide"
        );
    }
    ensure!(
        versions.contains(&catalog.recommended),
        "Version recommandée absente"
    );
    Ok(VerifiedCatalog {
        catalog,
        digest: hex::encode(Sha256::digest(bytes)),
    })
}

/// L'état est une simulation : l'intégration future devra le stocker de façon fiable.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct State {
    installed: Version,
    highest_metadata: u64,
    metadata_digest: Option<String>,
    hold_version: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    NoChange,
    Upgrade,
    ConfirmUserRollback,
    ConfirmPublisherRollback,
    UpdateAvailableWhileHeld,
}

#[derive(Clone, Debug)]
pub struct Plan {
    pub action: Action,
    target: Option<Target>,
    installed_at_plan: Version,
    metadata_version: u64,
    metadata_digest: String,
    hold_at_plan: bool,
}

pub struct VerifiedTarget {
    plan: Plan,
}

impl State {
    pub fn new(installed: &str) -> Result<Self> {
        let installed = Version::parse(installed)?;
        ensure!(
            installed.build.is_empty(),
            "Métadonnées de version non prises en charge"
        );
        Ok(Self {
            installed,
            highest_metadata: 0,
            metadata_digest: None,
            hold_version: false,
        })
    }

    /// À persister avant tout téléchargement ou installation en intégration réelle.
    pub fn observe(&mut self, catalog: &VerifiedCatalog) -> Result<()> {
        let version = catalog.catalog.metadata_version;
        ensure!(
            version >= self.highest_metadata,
            "Retour arrière des informations signées"
        );
        if version == self.highest_metadata {
            ensure!(
                self.metadata_digest.as_deref() == Some(&catalog.digest),
                "Informations différentes pour la même version"
            );
        } else {
            self.highest_metadata = version;
            self.metadata_digest = Some(catalog.digest.clone());
        }
        Ok(())
    }

    pub fn installed(&self) -> &Version {
        &self.installed
    }
    pub fn is_held(&self) -> bool {
        self.hold_version
    }
    pub fn resume_updates(&mut self) {
        self.hold_version = false;
    }

    /// `chosen` est une sélection explicite ; `None` suit la recommandation signée.
    pub fn plan(&self, catalog: &VerifiedCatalog, chosen: Option<&str>) -> Result<Plan> {
        ensure!(
            self.highest_metadata == catalog.catalog.metadata_version
                && self.metadata_digest.as_deref() == Some(&catalog.digest),
            "Catalogue non enregistré comme information de confiance"
        );
        let desired = match chosen {
            Some(value) => Version::parse(value)?,
            None => catalog.catalog.recommended.clone(),
        };
        let target = catalog
            .catalog
            .targets
            .iter()
            .find(|t| t.version == desired)
            .context("Version absente du catalogue signé")?;
        let ordering = desired.cmp_precedence(&self.installed);
        let action = if ordering == Ordering::Equal {
            Action::NoChange
        } else if chosen.is_none() && self.hold_version {
            Action::UpdateAvailableWhileHeld
        } else if ordering == Ordering::Less && chosen.is_some() {
            Action::ConfirmUserRollback
        } else if ordering == Ordering::Less {
            Action::ConfirmPublisherRollback
        } else {
            Action::Upgrade
        };
        Ok(Plan {
            action,
            target: Some(target.clone()),
            installed_at_plan: self.installed.clone(),
            metadata_version: self.highest_metadata,
            metadata_digest: catalog.digest.clone(),
            hold_at_plan: self.hold_version,
        })
    }

    /// Simule une installation réussie ou échouée ; ne modifie aucun exécutable.
    pub fn finish(
        &mut self,
        verified: VerifiedTarget,
        confirmed: bool,
        installed_successfully: bool,
    ) -> Result<()> {
        let plan = verified.plan;
        ensure!(
            self.highest_metadata == plan.metadata_version
                && self.metadata_digest.as_deref() == Some(&plan.metadata_digest)
                && self.installed == plan.installed_at_plan
                && self.hold_version == plan.hold_at_plan,
            "Décision périmée"
        );
        ensure!(
            matches!(
                plan.action,
                Action::Upgrade | Action::ConfirmUserRollback | Action::ConfirmPublisherRollback
            ),
            "Aucune installation autorisée"
        );
        if matches!(
            plan.action,
            Action::ConfirmUserRollback | Action::ConfirmPublisherRollback
        ) {
            ensure!(confirmed, "Le retour arrière doit être confirmé");
        }
        if installed_successfully {
            self.installed = plan.target.context("Version manquante")?.version;
            self.hold_version = matches!(
                plan.action,
                Action::ConfirmUserRollback | Action::ConfirmPublisherRollback
            );
        }
        Ok(())
    }
}

impl Plan {
    pub fn target_version(&self) -> Option<&Version> {
        self.target.as_ref().map(|t| &t.version)
    }

    pub fn verify_target<R: Read>(self, mut input: R) -> Result<VerifiedTarget> {
        ensure!(
            matches!(
                self.action,
                Action::Upgrade | Action::ConfirmUserRollback | Action::ConfirmPublisherRollback
            ),
            "Aucun fichier à installer"
        );
        let target = self.target.as_ref().context("Version manquante")?;
        let mut hasher = Sha256::new();
        let mut total = 0u64;
        let mut buf = [0u8; 8192];
        loop {
            let count = input.read(&mut buf)?;
            if count == 0 {
                break;
            }
            total += count as u64;
            ensure!(total <= target.size, "Fichier plus grand qu'annoncé");
            hasher.update(&buf[..count]);
        }
        ensure!(
            total == target.size
                && hex::encode(hasher.finalize()).eq_ignore_ascii_case(&target.sha256),
            "Taille ou empreinte incorrecte"
        );
        Ok(VerifiedTarget { plan: self })
    }
}

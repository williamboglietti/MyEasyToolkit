use met_verification_experimentale::rollback::{verify_catalog, Action, State, VerifiedCatalog};

const KEY: &[u8] = include_bytes!("fixtures/rollback-public.gpg");
const SIGNER: &str = include_str!("fixtures/rollback-signer.txt");
const FILE: &[u8] = include_bytes!("fixtures/fichier-test");

fn signed(bytes: &[u8], signature: &[u8], platform: &str) -> anyhow::Result<VerifiedCatalog> {
    verify_catalog(
        KEY,
        SIGNER.trim(),
        bytes,
        signature,
        platform,
        1_800_000_000,
    )
}

fn catalog(name: &str) -> VerifiedCatalog {
    let (bytes, signature, platform): (&[u8], &[u8], &str) = match name {
        "old" => (
            include_bytes!("fixtures/catalogue-ancien.json"),
            include_bytes!("fixtures/catalogue-ancien.json.asc"),
            "windows-amd64",
        ),
        "current" => (
            include_bytes!("fixtures/catalogue-courant.json"),
            include_bytes!("fixtures/catalogue-courant.json.asc"),
            "windows-amd64",
        ),
        "same" => (
            include_bytes!("fixtures/catalogue-equivoque.json"),
            include_bytes!("fixtures/catalogue-equivoque.json.asc"),
            "windows-amd64",
        ),
        "rollback" => (
            include_bytes!("fixtures/catalogue-retour-editeur.json"),
            include_bytes!("fixtures/catalogue-retour-editeur.json.asc"),
            "windows-amd64",
        ),
        "fixed" => (
            include_bytes!("fixtures/catalogue-correctif.json"),
            include_bytes!("fixtures/catalogue-correctif.json.asc"),
            "windows-amd64",
        ),
        "mac" => (
            include_bytes!("fixtures/catalogue-macos.json"),
            include_bytes!("fixtures/catalogue-macos.json.asc"),
            "darwin-arm64",
        ),
        _ => panic!("fixture inconnu"),
    };
    signed(bytes, signature, platform).expect("catalogue de test signé")
}

fn restart(state: &State) -> State {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("etat.json");
    std::fs::write(&path, serde_json::to_vec(state).unwrap()).unwrap();
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

#[test]
fn retour_choisi_confirme_puis_maintenu_sans_boucle() {
    for name in ["current", "mac"] {
        let catalog = catalog(name);
        let mut state = State::new("0.1.8").unwrap();
        state.observe(&catalog).unwrap();
        let plan = state.plan(&catalog, Some("0.1.7")).unwrap();
        assert_eq!(plan.action, Action::ConfirmUserRollback);
        assert_eq!(plan.target_version().unwrap().to_string(), "0.1.7");
        assert!(state
            .finish(plan.clone().verify_target(FILE).unwrap(), false, true)
            .is_err());
        assert_eq!(state.installed().to_string(), "0.1.8");
        state
            .finish(plan.clone().verify_target(FILE).unwrap(), true, false)
            .unwrap();
        assert_eq!(state.installed().to_string(), "0.1.8");
        state
            .finish(plan.verify_target(FILE).unwrap(), true, true)
            .unwrap();
        assert_eq!(state.installed().to_string(), "0.1.7");
        assert!(state.is_held());
        let mut restarted = restart(&state);
        restarted.observe(&catalog).unwrap();
        assert_eq!(
            restarted.plan(&catalog, None).unwrap().action,
            Action::UpdateAvailableWhileHeld
        );
        assert!(restarted.is_held());
    }
}

#[test]
fn recommandation_editeur_signee_confirmable_sans_boucle() {
    let current = catalog("current");
    let rollback = catalog("rollback");
    let fixed = catalog("fixed");
    let mut state = State::new("0.1.8").unwrap();
    state.observe(&current).unwrap();
    state.observe(&rollback).unwrap();
    let plan = state.plan(&rollback, None).unwrap();
    assert_eq!(plan.action, Action::ConfirmPublisherRollback);
    assert!(state
        .finish(plan.clone().verify_target(FILE).unwrap(), false, true)
        .is_err());
    state
        .finish(plan.verify_target(FILE).unwrap(), true, true)
        .unwrap();
    let mut state = restart(&state);
    assert_eq!(
        state.plan(&rollback, None).unwrap().action,
        Action::NoChange
    );
    state.observe(&fixed).unwrap();
    assert_eq!(
        state.plan(&fixed, None).unwrap().action,
        Action::UpdateAvailableWhileHeld
    );
    state.resume_updates();
    let update = state.plan(&fixed, None).unwrap();
    assert_eq!(update.action, Action::Upgrade);
    state
        .finish(update.verify_target(FILE).unwrap(), false, true)
        .unwrap();
    assert_eq!(state.installed().to_string(), "0.1.9");
    assert!(!state.is_held());
}

#[test]
fn refuse_ancien_catalogue_ou_contenu_different_au_meme_numero() {
    let mut state = State::new("0.1.8").unwrap();
    state.observe(&catalog("current")).unwrap();
    let mut state = restart(&state);
    assert!(state.observe(&catalog("old")).is_err());
    assert!(state.observe(&catalog("same")).is_err());
    assert!(state.plan(&catalog("old"), None).is_err());
    state.observe(&catalog("current")).unwrap();
    assert_eq!(
        state.plan(&catalog("current"), None).unwrap().action,
        Action::NoChange
    );
}

#[test]
fn conserve_la_protection_si_l_installation_echoue() {
    let old = catalog("current");
    let new = catalog("rollback");
    let mut state = State::new("0.1.8").unwrap();
    state.observe(&old).unwrap();
    state.observe(&new).unwrap();
    let file = state.plan(&new, None).unwrap().verify_target(FILE).unwrap();
    state.finish(file, true, false).unwrap();
    let mut restarted = restart(&state);
    assert_eq!(restarted.installed().to_string(), "0.1.8");
    assert!(restarted.observe(&old).is_err());
    assert_eq!(
        restarted.plan(&new, None).unwrap().action,
        Action::ConfirmPublisherRollback
    );
}

#[test]
fn refuse_fichier_modifie_confirmation_perimee_et_version_absente() {
    let current = catalog("current");
    let mut state = State::new("0.1.8").unwrap();
    state.observe(&current).unwrap();
    assert!(state.plan(&current, Some("0.1.1")).is_err());
    let plan = state.plan(&current, Some("0.1.7")).unwrap();
    assert!(plan
        .clone()
        .verify_target(b"fichier modifie".as_slice())
        .is_err());
    let file = plan.verify_target(FILE).unwrap();
    state.observe(&catalog("fixed")).unwrap();
    assert!(state.finish(file, true, true).is_err());
    assert_eq!(state.installed().to_string(), "0.1.8");
}

#[test]
fn refuse_catalogue_non_signe_expire_ou_pour_une_autre_plateforme() {
    let bytes = include_bytes!("fixtures/catalogue-courant.json");
    let sig = include_bytes!("fixtures/catalogue-courant.json.asc");
    assert!(signed(b"{}", sig, "windows-amd64").is_err());
    assert!(signed(bytes, sig, "darwin-arm64").is_err());
    assert!(signed(
        include_bytes!("fixtures/catalogue-expire.json"),
        include_bytes!("fixtures/catalogue-expire.json.asc"),
        "windows-amd64"
    )
    .is_err());
}

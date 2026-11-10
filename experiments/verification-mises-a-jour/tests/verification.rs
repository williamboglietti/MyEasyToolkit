use met_verification_experimentale::verify;

const KEY: &[u8] = include_bytes!("fixtures/test-public.gpg");
const SIGNER: &str = include_str!("fixtures/signer.txt");
const DATA: &[u8] = include_bytes!("fixtures/fichier-test");

fn check(manifest: &[u8], signature: &[u8], data: &[u8], platform: &str, signer: &str) -> bool {
    verify(
        KEY,
        signer.trim(),
        manifest,
        signature,
        data,
        platform,
        1_800_000_000,
    )
    .is_ok()
}

#[test]
fn accepte_une_mise_a_jour_signee() {
    verify(
        KEY,
        SIGNER.trim(),
        include_bytes!("fixtures/valide.json"),
        include_bytes!("fixtures/valide.json.asc"),
        DATA,
        "windows-amd64",
        1_800_000_000,
    )
    .expect("la mise à jour Windows de test doit être valide");
    verify(
        KEY,
        SIGNER.trim(),
        include_bytes!("fixtures/valide-macos.json"),
        include_bytes!("fixtures/valide-macos.json.asc"),
        DATA,
        "darwin-arm64",
        1_800_000_000,
    )
    .expect("la mise à jour macOS de test doit être valide");
}

#[test]
fn refuse_toute_alteration_ou_cle_non_autorisee() {
    let m = include_bytes!("fixtures/valide.json");
    let s = include_bytes!("fixtures/valide.json.asc");
    assert!(!check(b"{}", s, DATA, "windows-amd64", SIGNER));
    assert!(!check(m, s, b"fichier modifie", "windows-amd64", SIGNER));
    assert!(!check(
        m,
        b"signature modifiee",
        DATA,
        "windows-amd64",
        SIGNER
    ));
    assert!(!check(m, s, DATA, "windows-arm64", SIGNER));
    assert!(!check(
        m,
        s,
        DATA,
        "windows-amd64",
        "0000000000000000000000000000000000000000"
    ));
}

#[test]
fn refuse_manifeste_signe_mais_incorrect() {
    for (m, s) in [
        (
            &include_bytes!("fixtures/expire.json")[..],
            &include_bytes!("fixtures/expire.json.asc")[..],
        ),
        (
            &include_bytes!("fixtures/nom-incorrect.json")[..],
            &include_bytes!("fixtures/nom-incorrect.json.asc")[..],
        ),
        (
            &include_bytes!("fixtures/taille-incorrecte.json")[..],
            &include_bytes!("fixtures/taille-incorrecte.json.asc")[..],
        ),
        (
            &include_bytes!("fixtures/hash-incorrect.json")[..],
            &include_bytes!("fixtures/hash-incorrect.json.asc")[..],
        ),
        (
            &include_bytes!("fixtures/plateforme-incorrecte.json")[..],
            &include_bytes!("fixtures/plateforme-incorrecte.json.asc")[..],
        ),
    ] {
        assert!(!check(m, s, DATA, "windows-amd64", SIGNER));
    }
}

#[test]
fn refuse_un_certificat_expire_meme_si_la_signature_est_ancienne() {
    let result = verify(
        include_bytes!("fixtures/expired-public.gpg"),
        include_str!("fixtures/expired-signer.txt").trim(),
        include_bytes!("fixtures/valide.json"),
        include_bytes!("fixtures/expired-key.asc"),
        DATA,
        "windows-amd64",
        1_800_000_000,
    );
    assert!(result.is_err());
}

#[test]
fn refuse_un_certificat_revoque() {
    assert!(verify(
        include_bytes!("fixtures/revoked-public.gpg"),
        include_str!("fixtures/revoked-signer.txt").trim(),
        include_bytes!("fixtures/valide.json"),
        include_bytes!("fixtures/revoked-key.asc"),
        DATA,
        "windows-amd64",
        1_800_000_000,
    )
    .is_err());
}

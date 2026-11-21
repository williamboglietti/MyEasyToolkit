//! Vérifie une signature détachée existante, sans installer le fichier.
use anyhow::{bail, Result};
use std::{env, fs};

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 3 {
        bail!("Usage : signature-production FICHIER SIGNATURE");
    }
    let key = include_bytes!("../../../packaging/myeasytoolkit-archive-keyring.gpg");
    let signer = "A0EF38D209213D2AB5761B814BBD7ACB126A6842";
    met_verification_experimentale::verify_signature(
        key,
        signer,
        &fs::read(&args[1])?,
        &fs::read(&args[2])?,
    )?;
    println!("Signature MyEasyToolkit vérifiée");
    Ok(())
}

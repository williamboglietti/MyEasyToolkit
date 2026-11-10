//! Vérifie une signature détachée existante, sans installer le fichier.
use anyhow::{bail, Result};
use std::{env, fs};

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 3 {
        bail!("Usage : signature-production FICHIER SIGNATURE");
    }
    let key = include_bytes!("../../../packaging/myeasytoolkit-archive-keyring.gpg");
    let signer = "2EA0195379DBCEAA17B69B0D660BE4A46617BD54";
    met_verification_experimentale::verify_signature(
        key,
        signer,
        &fs::read(&args[1])?,
        &fs::read(&args[2])?,
    )?;
    println!("Signature MyEasyToolkit vérifiée");
    Ok(())
}

use anyhow::{bail, Result};
use std::{
    env, fs,
    time::{SystemTime, UNIX_EPOCH},
};

const KEY: &[u8] = include_bytes!("../../../packaging/myeasytoolkit-archive-keyring.gpg");
const SIGNER: &str = "A0EF38D209213D2AB5761B814BBD7ACB126A6842";

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 5 {
        bail!("Usage expérimental : met-verification-experimentale MANIFESTE SIGNATURE FICHIER PLATEFORME");
    }
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let result = met_verification_experimentale::verify(
        KEY,
        SIGNER,
        &fs::read(&args[1])?,
        &fs::read(&args[2])?,
        fs::File::open(&args[3])?,
        &args[4],
        now,
    )?;
    println!(
        "Signature et fichier vérifiés : {} ({})",
        result.version, result.platform
    );
    Ok(())
}

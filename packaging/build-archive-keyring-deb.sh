#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 PUBLIC_KEYRING PRIMARY_FINGERPRINTS_CSV VERSION" >&2
  exit 2
fi
keyring="$1"
fingerprint="$2"
version="$3"
if [[ "$(uname -s)" != Linux ]]; then
  echo 'La construction du paquet Debian doit être effectuée sous Linux.' >&2
  exit 1
fi
if [[ ! -f "$keyring" || ! "$fingerprint" =~ ^[A-F0-9]{40}(,[A-F0-9]{40})*$ ]]; then
  echo 'Fichier de clés ou empreinte OpenPGP invalide.' >&2
  exit 1
fi
if ! dpkg --validate-version "$version"; then
  echo 'Version Debian invalide.' >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -m 700 "$work_dir/gnupg"
cp "$keyring" "$work_dir/public-keyring.gpg"
keyring="$work_dir/public-keyring.gpg"
# Ne jamais emballer de clé privée, même fournie par erreur.
LC_ALL=C gpg --homedir "$work_dir/gnupg" --batch --list-packets "$keyring" > "$work_dir/packets"
if grep -Eq '^:secret (sub )?key packet:' "$work_dir/packets"; then
  echo 'Le fichier contient une clé privée ; seule une clé publique est autorisée.' >&2
  exit 1
fi
gpg --homedir "$work_dir/gnupg" --batch --show-keys --with-colons "$keyring" > "$work_dir/key-info"
awk -F: '$1 == "pub" { primary=1; next } primary && $1 == "fpr" { print $10; primary=0 }' "$work_dir/key-info" | LC_ALL=C sort > "$work_dir/actual-fingerprints"
printf '%s\n' "$fingerprint" | tr ',' '\n' | LC_ALL=C sort > "$work_dir/expected-fingerprints"
if [[ ! -s "$work_dir/actual-fingerprints" ]] || ! cmp -s "$work_dir/actual-fingerprints" "$work_dir/expected-fingerprints"; then
  echo "Les clés publiques ne correspondent pas aux empreintes attendues." >&2
  exit 1
fi
# APT sur les anciennes versions de Debian attend un trousseau binaire.
if LC_ALL=C grep -q '^-----BEGIN PGP' "$keyring"; then
  echo 'Fournissez un trousseau public binaire, non blindé ASCII.' >&2
  exit 1
fi

install -d "$work_dir/package/DEBIAN" "$work_dir/package/usr/share/keyrings"
install -m 644 "$keyring" "$work_dir/package/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg"
cat > "$work_dir/package/DEBIAN/control" <<CONTROL
Package: myeasytoolkit-archive-keyring
Version: $version
Section: misc
Priority: optional
Architecture: all
Maintainer: MyEasyToolkit
Description: Public signing keys for the MyEasyToolkit APT repository
 Public OpenPGP keyring used to authenticate the MyEasyToolkit APT repository.
CONTROL
mkdir -p dist/keyring
dpkg-deb -Zxz --build --root-owner-group "$work_dir/package" "dist/keyring/myeasytoolkit-archive-keyring_${version}_all.deb"

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 && $# -ne 4 ]]; then
  echo "Usage: $0 PACKAGES_DIR OUTPUT_DIR SIGNING_KEY_FINGERPRINT [KEYRING_DEB]" >&2
  exit 2
fi
packages_dir="$1"
output_dir="$2"
signing_key="$3"
suite="${MET_APT_SUITE:-stable}"
signing_subkey="${MET_APT_SIGNING_SUBKEY:-}"
case "$suite" in stable|testing) ;; *) echo 'Canal APT invalide : utiliser stable ou testing.' >&2; exit 1 ;; esac
if [[ -e "$output_dir" ]]; then
  echo "Le répertoire de sortie existe déjà : $output_dir" >&2
  exit 1
fi
if [[ ! "$signing_key" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  echo 'Indiquez une empreinte OpenPGP complète de 40 caractères.' >&2
  exit 1
fi
if [[ -n "$signing_subkey" ]]; then
  [[ "$signing_subkey" =~ ^[A-F0-9]{40}$ ]] || { echo 'Empreinte de sous-clé invalide.' >&2; exit 1; }
  if ! gpg --batch --with-colons --with-fingerprint --with-subkey-fingerprint --list-keys "$signing_key" |
    awk -F: -v expected="$signing_subkey" '$1 == "sub" { subkey=1; next } subkey && $1 == "fpr" { if ($10 == expected) found=1; subkey=0 } END { exit !found }'; then
    echo 'La sous-clé ne correspond pas à la clé principale du dépôt.' >&2; exit 1
  fi
  sign_args=(--batch --yes --local-user "$signing_subkey!")
else
  [[ "$suite" != testing ]] || { echo 'Le canal testing exige une sous-clé de signature explicite.' >&2; exit 1; }
  sign_args=(--batch --yes --local-user "$signing_key")
fi
if [[ -n "${MET_GPG_PASSPHRASE_FILE:-}" ]]; then
  sign_args+=(--pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE")
fi
shopt -s nullglob
packages=("$packages_dir"/*.deb)
if [[ ${#packages[@]} -eq 0 ]]; then
  echo 'Aucun paquet Debian trouvé.' >&2
  exit 1
fi
for package in "${packages[@]}"; do
  if [[ "$(dpkg-deb -f "$package" Package)" != myeasytoolkit ]]; then
    echo "Paquet inattendu : $package" >&2
    exit 1
  fi
  case "$(dpkg-deb -f "$package" Architecture)" in
    amd64|arm64) ;;
    *) echo "Architecture inattendue : $package" >&2; exit 1 ;;
  esac
done
mkdir -p "$output_dir/pool/main/m/myeasytoolkit" "$output_dir/dists/$suite/main/binary-amd64" "$output_dir/dists/$suite/main/binary-arm64"
cp "${packages[@]}" "$output_dir/pool/main/m/myeasytoolkit/"
if [[ $# -eq 4 ]]; then
  keyring_deb="$4"
  [[ -f "$keyring_deb" && "$(dpkg-deb -f "$keyring_deb" Package)" == myeasytoolkit-archive-keyring && "$(dpkg-deb -f "$keyring_deb" Architecture)" == all ]] || { echo 'Paquet de clés invalide.' >&2; exit 1; }
  mkdir -p "$output_dir/pool/main/m/myeasytoolkit-archive-keyring"
  cp "$keyring_deb" "$output_dir/pool/main/m/myeasytoolkit-archive-keyring/"
fi
(
  cd "$output_dir"
  for arch in amd64 arm64; do
    dpkg-scanpackages --multiversion --arch "$arch" pool /dev/null > "dists/$suite/main/binary-$arch/Packages"
    gzip -n -c "dists/$suite/main/binary-$arch/Packages" > "dists/$suite/main/binary-$arch/Packages.gz"
  done
  apt-ftparchive -o APT::FTPArchive::Release::Origin=MyEasyToolkit \
    -o APT::FTPArchive::Release::Label=MyEasyToolkit \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o 'APT::FTPArchive::Release::Architectures=amd64 arm64' \
    -o APT::FTPArchive::Release::Components=main \
    release "dists/$suite" > "dists/$suite/Release"
  gpg "${sign_args[@]}" --clearsign --output "dists/$suite/InRelease" "dists/$suite/Release"
  gpg "${sign_args[@]}" --armor --detach-sign --output "dists/$suite/Release.gpg" "dists/$suite/Release"
  gpg --batch --export "$signing_key" > myeasytoolkit-archive-keyring.gpg
  test -s myeasytoolkit-archive-keyring.gpg
)

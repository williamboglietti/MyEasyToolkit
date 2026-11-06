#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 PACKAGES_DIR OUTPUT_DIR SIGNING_KEY_FINGERPRINT" >&2
  exit 2
fi
packages_dir="$1"
output_dir="$2"
signing_key="$3"
if [[ -e "$output_dir" ]]; then
  echo "Le répertoire de sortie existe déjà : $output_dir" >&2
  exit 1
fi
if [[ ! "$signing_key" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  echo 'Indiquez une empreinte OpenPGP complète de 40 caractères.' >&2
  exit 1
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
mkdir -p "$output_dir/pool/main/m/myeasytoolkit" "$output_dir/dists/stable/main/binary-amd64" "$output_dir/dists/stable/main/binary-arm64"
cp "${packages[@]}" "$output_dir/pool/main/m/myeasytoolkit/"
(
  cd "$output_dir"
  for arch in amd64 arm64; do
    dpkg-scanpackages --multiversion --arch "$arch" pool /dev/null > "dists/stable/main/binary-$arch/Packages"
    gzip -n -c "dists/stable/main/binary-$arch/Packages" > "dists/stable/main/binary-$arch/Packages.gz"
  done
  apt-ftparchive -o APT::FTPArchive::Release::Origin=MyEasyToolkit \
    -o APT::FTPArchive::Release::Label=MyEasyToolkit \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o 'APT::FTPArchive::Release::Architectures=amd64 arm64' \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable > dists/stable/Release
  gpg --batch --yes --local-user "$signing_key" --clearsign --output dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --local-user "$signing_key" --armor --detach-sign --output dists/stable/Release.gpg dists/stable/Release
  gpg --batch --export "$signing_key" > myeasytoolkit-archive-keyring.gpg
  test -s myeasytoolkit-archive-keyring.gpg
)

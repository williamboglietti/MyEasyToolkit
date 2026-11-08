#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 && $# -ne 6 ]]; then
  echo "Usage: $0 ARTIFACTS_DIR OUTPUT_DIR SIGNING_KEY_FINGERPRINT [PUBLIC_KEYRING FINGERPRINTS_CSV KEYRING_VERSION]" >&2
  exit 2
fi
artifacts_dir="$1"
output_dir="$2"
fingerprint="$3"
if [[ -e "$output_dir" ]]; then echo "Le répertoire de sortie existe déjà : $output_dir" >&2; exit 1; fi
if [[ ! "$fingerprint" =~ ^[A-F0-9]{40}$ ]]; then echo 'Empreinte invalide.' >&2; exit 1; fi
files=(
  myeasytoolkit-darwin-amd64.tar.gz
  myeasytoolkit-darwin-arm64.tar.gz
  myeasytoolkit-linux-amd64.tar.gz
  myeasytoolkit-linux-arm64.tar.gz
  myeasytoolkit-windows-amd64.exe
  myeasytoolkit-windows-arm64.exe
)
for file in "${files[@]}"; do
  if [[ ! -f "$artifacts_dir/$file" ]]; then echo "Fichier manquant : $file" >&2; exit 1; fi
done
shopt -s nullglob
packages=("$artifacts_dir"/*.deb)
declare -A packages_by_arch=()
version=''
for package in "${packages[@]}"; do
  [[ "$(dpkg-deb -f "$package" Package)" == myeasytoolkit ]] || { echo 'Paquet Debian inattendu.' >&2; exit 1; }
  arch="$(dpkg-deb -f "$package" Architecture)"
  case "$arch" in amd64|arm64) ;; *) echo 'Architecture Debian inattendue.' >&2; exit 1 ;; esac
  [[ -z "${packages_by_arch[$arch]:-}" ]] || { echo "Plusieurs paquets pour $arch." >&2; exit 1; }
  package_version="$(dpkg-deb -f "$package" Version)"
  [[ -z "$version" || "$version" == "$package_version" ]] || { echo 'Versions Debian incohérentes.' >&2; exit 1; }
  version="$package_version"
  packages_by_arch[$arch]="$package"
done
for arch in amd64 arm64; do
  [[ -n "${packages_by_arch[$arch]:-}" ]] || { echo "Paquet $arch manquant." >&2; exit 1; }
done
mkdir -p "$output_dir/releases/latest"
for file in "${files[@]}"; do
  cp "$artifacts_dir/$file" "$output_dir/releases/latest/$file"
  (cd "$output_dir/releases/latest" && sha256sum "$file" > "$file.sha256")
done
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keyring_work="$(mktemp -d)"
trap 'rm -rf "$keyring_work"' EXIT
if [[ $# -eq 6 ]]; then
  cp "$4" "$keyring_work/public.gpg"
  keyring_fingerprints="$5"
  keyring_version="$6"
else
  gpg --batch --export "$fingerprint" > "$keyring_work/public.gpg"
  keyring_fingerprints="$fingerprint"
  keyring_version="$version"
fi
case ",$keyring_fingerprints," in
  *",$fingerprint,"*) ;;
  *) echo 'La clé de signature doit être présente dans le paquet de clés.' >&2; exit 1 ;;
esac
(cd "$keyring_work" && bash "$repo_root/packaging/build-archive-keyring-deb.sh" public.gpg "$keyring_fingerprints" "$keyring_version")
MET_APT_SUITE=stable bash packaging/build-apt-repository.sh "$artifacts_dir" "$output_dir/apt" "$fingerprint" "$keyring_work/dist/keyring/myeasytoolkit-archive-keyring_${keyring_version}_all.deb"
apt_keyring="$(cd "$output_dir/apt" && pwd)/myeasytoolkit-archive-keyring.gpg"
signer="$(gpgv --status-fd 1 --keyring "$apt_keyring" "$output_dir/apt/dists/stable/InRelease" 2>/dev/null | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3 }')"
[[ "$signer" =~ ^[A-F0-9]{40}$ ]] || { echo 'Empreinte du signataire APT invalide.' >&2; exit 1; }
sign_args=(--batch --yes --local-user "$fingerprint")
if [[ -n "${MET_GPG_PASSPHRASE_FILE:-}" ]]; then
  sign_args+=(--pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE")
fi
for arch in amd64 arm64; do
  asset="$output_dir/releases/latest/myeasytoolkit-linux-$arch.deb"
  cp "${packages_by_arch[$arch]}" "$asset"
  gpg "${sign_args[@]}" --armor --detach-sign --output "$asset.asc" "$asset"
  gpgv --keyring "$output_dir/apt/myeasytoolkit-archive-keyring.gpg" "$asset.asc" "$asset"
  (cd "$output_dir/releases/latest" && sha256sum "$(basename "$asset")" > "$(basename "$asset").sha256")
done
sed -e "s/__APT_FINGERPRINT__/$fingerprint/" -e "s/__APT_SIGNER_FINGERPRINT__/$signer/" installers/install.sh > "$output_dir/install.sh"
cp installers/install.ps1 "$output_dir/install.ps1"
cat > "$output_dir/_headers" <<'HEADERS'
/install.sh
  Content-Type: text/plain; charset=utf-8
  X-Content-Type-Options: nosniff
/install.ps1
  Content-Type: text/plain; charset=utf-8
  X-Content-Type-Options: nosniff
HEADERS
chmod 644 "$output_dir/install.sh" "$output_dir/install.ps1"

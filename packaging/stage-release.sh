#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 ARTIFACTS_DIR OUTPUT_DIR SIGNING_KEY_FINGERPRINT" >&2
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
mkdir -p "$output_dir/releases/latest"
for file in "${files[@]}"; do
  cp "$artifacts_dir/$file" "$output_dir/releases/latest/$file"
  (cd "$output_dir/releases/latest" && sha256sum "$file" > "$file.sha256")
done
bash packaging/build-apt-repository.sh "$artifacts_dir" "$output_dir/apt" "$fingerprint"
sed "s/__APT_FINGERPRINT__/$fingerprint/" installers/install.sh > "$output_dir/install.sh"
cp installers/install.ps1 "$output_dir/install.ps1"
chmod 644 "$output_dir/install.sh" "$output_dir/install.ps1"

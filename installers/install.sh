#!/usr/bin/env bash
set -euo pipefail

base_url='https://packages.myeasytoolkit.com'
apt_fingerprint='__APT_FINGERPRINT__'
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

run_root() {
  if [[ "$(id -u)" == 0 ]]; then "$@"; else sudo "$@"; fi
}

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo 'Architecture non prise en charge.' >&2; exit 1 ;;
esac

if [[ "$(uname -s)" == Linux ]] && command -v apt-get >/dev/null; then
  apt_arch="$(dpkg --print-architecture)"
  case "$apt_arch" in
    amd64|arm64) ;;
    *) echo "Architecture Debian non prise en charge : $apt_arch" >&2; exit 1 ;;
  esac
  if [[ ! "$apt_fingerprint" =~ ^[A-F0-9]{40}$ ]]; then
    echo 'Installateur incomplet : empreinte de signature absente.' >&2; exit 1
  fi
  if ! command -v gpg >/dev/null; then
    run_root apt-get update
    run_root apt-get install -y gnupg ca-certificates
  fi
  curl -fsSL "$base_url/apt/myeasytoolkit-archive-keyring.gpg" -o "$work_dir/keyring.gpg"
  gpg --batch --show-keys --with-colons "$work_dir/keyring.gpg" > "$work_dir/key-info"
  actual_fingerprint="$(awk -F: '$1 == "fpr" { print $10; exit }' "$work_dir/key-info")"
  primary_count="$(awk -F: '$1 == "pub" { count++ } END { print count+0 }' "$work_dir/key-info")"
  if [[ "$actual_fingerprint" != "$apt_fingerprint" || "$primary_count" != 1 ]]; then
    echo 'La clé du dépôt ne correspond pas à la clé attendue.' >&2; exit 1
  fi
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg] %s/apt stable main\n' "$apt_arch" "$base_url" > "$work_dir/myeasytoolkit.list"
  run_root install -m 644 "$work_dir/keyring.gpg" /usr/share/keyrings/myeasytoolkit-archive-keyring.gpg
  run_root install -m 644 "$work_dir/myeasytoolkit.list" /etc/apt/sources.list.d/myeasytoolkit.list
  run_root apt-get update
  run_root apt-get install -y myeasytoolkit-archive-keyring myeasytoolkit
  echo 'Installation terminée. Lancez : myeasytoolkit'
  exit 0
fi

case "$(uname -s)" in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *) echo 'Système non pris en charge par cet installateur.' >&2; exit 1 ;;
esac
file="myeasytoolkit-$platform-$arch.tar.gz"
curl -fsSL "$base_url/releases/latest/$file" -o "$work_dir/$file"
curl -fsSL "$base_url/releases/latest/$file.sha256" -o "$work_dir/$file.sha256"
expected="$(awk 'NR == 1 {print $1}' "$work_dir/$file.sha256")"
if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then echo 'Somme de contrôle invalide.' >&2; exit 1; fi
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "$work_dir/$file" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$work_dir/$file" | awk '{print $1}')"
fi
if [[ "$actual" != "$expected" ]]; then echo 'La somme de contrôle ne correspond pas.' >&2; exit 1; fi
bin_dir="${MET_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$work_dir/unpacked" "$bin_dir"
tar -xzf "$work_dir/$file" -C "$work_dir/unpacked"
install -m 755 "$work_dir/unpacked/myeasytoolkit" "$bin_dir/myeasytoolkit"
printf 'Installation terminée : %s/myeasytoolkit\n' "$bin_dir"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) printf "Pour cette session, exécutez : export PATH=%q:\"\$PATH\"\n" "$bin_dir" ;;
esac

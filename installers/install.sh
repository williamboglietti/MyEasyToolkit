#!/usr/bin/env bash
set -euo pipefail

base_url='https://packages.myeasytoolkit.com'
mode='__APT_MODE__'
case "$mode" in repair|uninstall) ;; *) mode=install ;; esac
if [[ "$(uname -s)" == Linux ]] && command -v apt-get >/dev/null; then
  if [[ ! -x /usr/bin/python3 ]]; then
    echo 'Python 3 est requis pour les opérations APT MyEasyToolkit.' >&2
    exit 1
  fi
  root=()
  if [[ "$(id -u)" != 0 ]]; then root=(sudo --); fi
  exec "${root[@]}" /usr/bin/python3 -I - "$mode" "$base_url" \
    '__APT_FINGERPRINT__' '__APT_SIGNER_FINGERPRINT__' '__APT_KEY_SHA256__' \
    '__APT_BINARY_SHA256__' '__APT_README_SHA256__' <<'MET_APT_MAINTENANCE'
__APT_MAINTENANCE__
MET_APT_MAINTENANCE
elif [[ "$mode" != install ]]; then
  echo 'Ce lanceur est réservé à Linux avec APT.' >&2
  exit 1
fi
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo 'Architecture non prise en charge.' >&2; exit 1 ;;
esac

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

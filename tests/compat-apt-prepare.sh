#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo 'Usage: compat-apt-prepare.sh PACKAGES_DIR OUTPUT_DIR' >&2
  exit 2
fi
packages_dir="$(cd "$1" && pwd)"
output_dir="$2"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
key_dir="$(mktemp -d)"
trap 'gpgconf --homedir "$key_dir" --kill gpg-agent || true; rm -rf "$key_dir"' EXIT
chmod 700 "$key_dir"
export GNUPGHOME="$key_dir"

for algo in ed25519 rsa4096; do
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "CI $algo <test@example.invalid>" "$algo" cert 1d
  fingerprint="$(gpg --batch --with-colons --list-keys "CI $algo" | awk -F: '$1 == "fpr" {print $10; exit}')"
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$fingerprint" "$algo" sign 1d
  gpg --batch --export "$fingerprint" > "$output_dir/$algo.gpg"
  bash packaging/build-apt-repository.sh "$packages_dir" "$output_dir/$algo" "$fingerprint"
done
chmod -R a+rX "$output_dir"

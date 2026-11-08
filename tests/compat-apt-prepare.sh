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
cleanup() {
  for met_home in "$key_dir" "$key_dir/stable" "$key_dir/testing"; do
    gpgconf --homedir "$met_home" --kill gpg-agent >/dev/null 2>&1 || true
  done
  rm -rf "$key_dir"
}
trap cleanup EXIT
chmod 700 "$key_dir"
export GNUPGHOME="$key_dir"
unset MET_GPG_PASSPHRASE_FILE MET_APT_SUITE MET_APT_SIGNING_SUBKEY

for algo in ed25519 rsa4096; do
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "CI $algo <test@example.invalid>" "$algo" cert 1d
  fingerprint="$(gpg --batch --with-colons --list-keys "CI $algo" | awk -F: '$1 == "fpr" {print $10; exit}')"
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$fingerprint" "$algo" sign 1d
  gpg --batch --export "$fingerprint" > "$output_dir/$algo.gpg"
  bash packaging/build-apt-repository.sh "$packages_dir" "$output_dir/$algo" "$fingerprint"
  if [[ "$algo" == rsa4096 ]]; then
    # Deux CI distinctes : chacune ne reçoit que sa propre sous-clé privée.
    gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$fingerprint" "$algo" sign 1d
    mapfile -t channel_subkeys < <(gpg --batch --with-colons --with-subkey-fingerprint --list-keys "$fingerprint" | awk -F: '$1 == "sub" { next_fpr=1; next } next_fpr && $1 == "fpr" { print $10; next_fpr=0 }')
    [[ ${#channel_subkeys[@]} -eq 2 && "${channel_subkeys[0]}" != "${channel_subkeys[1]}" ]]
    gpg --batch --export "$fingerprint" > "$output_dir/channels.gpg"
    printf '%s\n%s\n' "${channel_subkeys[0]}" "${channel_subkeys[1]}" > "$output_dir/channel-signers.txt"
    for index in 0 1; do
      if [[ "$index" == 0 ]]; then channel=stable; else channel=testing; fi
      channel_home="$key_dir/$channel"
      mkdir -m 700 "$channel_home"
      gpg --batch --pinentry-mode loopback --passphrase '' --export-secret-subkeys "${channel_subkeys[$index]}!" > "$key_dir/$channel.asc"
      gpg --homedir "$channel_home" --batch --import "$key_dir/$channel.asc"
      gpg --homedir "$channel_home" --batch --with-colons --with-subkey-fingerprint --list-secret-keys "$fingerprint" > "$key_dir/$channel-secret-info"
      awk -F: -v expected="${channel_subkeys[$index]}" '
        $1 == "sec" { if ($15 != "#") bad=1; primary=1 }
        $1 == "ssb" { count++; if ($15 == "#") bad=1; selected=1; next }
        selected && $1 == "fpr" { if ($10 != expected) bad=1; selected=0 }
        END { exit !(primary && count == 1 && !bad) }
      ' "$key_dir/$channel-secret-info"
      MET_APT_SUITE="$channel" MET_APT_SIGNING_SUBKEY="${channel_subkeys[$index]}" GNUPGHOME="$channel_home" \
        bash packaging/build-apt-repository.sh "$packages_dir" "$output_dir/channel-$channel" "$fingerprint"
      actual="$(gpgv --status-fd 1 --keyring "$output_dir/channels.gpg" "$output_dir/channel-$channel/dists/$channel/InRelease" 2>/dev/null | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3 }')"
      [[ "$actual" == "${channel_subkeys[$index]}" ]]
    done
  fi
done
chmod -R a+rX "$output_dir"

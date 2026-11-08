#!/usr/bin/env bash
set -euo pipefail

[[ -n "${SIGNING_KEY:-}" && -n "${SIGNING_PASSPHRASE:-}" ]] || { echo 'Secrets de signature absents.' >&2; exit 1; }
work_dir="$(mktemp -d)"
export GNUPGHOME="$work_dir/gnupg"
mkdir -m 700 "$GNUPGHOME"
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$work_dir"' EXIT
printf '%s' "$SIGNING_KEY" | gpg --batch --import
printf '%s' "$SIGNING_PASSPHRASE" > "$work_dir/passphrase"
chmod 600 "$work_dir/passphrase"
gpg --batch --with-colons --with-subkey-fingerprint --list-secret-keys > "$work_dir/secret-info"
expected="$(tr -d '\r\n' < packaging/archive-fingerprint.txt)"
primary="$(awk -F: '$1 == "sec" { if ($15 != "#") exit 1; next_key=1; next } next_key && $1 == "fpr" { print $10; exit }' "$work_dir/secret-info")"
[[ "$primary" == "$expected" ]] || { echo 'Clé principale privée présente ou empreinte incorrecte.' >&2; exit 1; }
signer="$(awk -F: '$1 == "ssb" { if ($15 != "+" || !index($12, "s")) exit 1; count++; next_key=1; next } next_key && $1 == "fpr" { print $10; next_key=0 } END { if (count != 1) exit 1 }' "$work_dir/secret-info")"
[[ "$signer" =~ ^[A-F0-9]{40}$ ]] || { echo 'Sous-clé de signature absente ou ambiguë.' >&2; exit 1; }
gpg --batch --export "$signer!" > "$work_dir/public.gpg"
cmp "$work_dir/public.gpg" packaging/myeasytoolkit-archive-keyring.gpg || { echo 'Trousseau public différent du signataire CI.' >&2; exit 1; }
printf 'MyEasyToolkit CI signing verification\n' > "$work_dir/test.txt"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$work_dir/passphrase" \
  --local-user "$signer!" --output "$work_dir/test.sig" --detach-sign "$work_dir/test.txt"
gpgv --keyring "$work_dir/public.gpg" "$work_dir/test.sig" "$work_dir/test.txt"
printf 'Sous-clé et phrase CI vérifiées sans publication.\n'

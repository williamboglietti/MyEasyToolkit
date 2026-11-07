#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 && $# -ne 8 ]]; then
  echo "Usage: $0 PROJECT_KEYRING PROJECT_FINGERPRINT VERSION AUTHORITY_KEYRING AUTHORITY_FINGERPRINT PROJECT_UID [CATALOG_URL REPO_HOST]" >&2
  exit 2
fi
keyring="$1"
fingerprint="$2"
version="$3"
authority="$4"
authority_fingerprint="$5"
project_uid="$6"
catalog_url="${7:-https://packages.myeasytoolkit.com/apt/certificates.gpg}"
repo_host="${8:-packages.myeasytoolkit.com}"
if [[ "$(uname -s)" != Linux ]]; then
  echo 'La construction du paquet Debian doit être effectuée sous Linux.' >&2
  exit 1
fi
if [[ ! -f "$keyring" || ! -f "$authority" || ! "$fingerprint" =~ ^[A-F0-9]{40}$ || ! "$authority_fingerprint" =~ ^[A-F0-9]{40}$ ]]; then
  echo 'Fichier de clés ou empreinte OpenPGP invalide.' >&2
  exit 1
fi
if ! dpkg --validate-version "$version"; then
  echo 'Version Debian invalide.' >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
actual_fingerprint="$(awk -F: '$1 == "fpr" { print $10; exit }' "$work_dir/key-info")"
primary_count="$(awk -F: '$1 == "pub" { count++ } END { print count+0 }' "$work_dir/key-info")"
if [[ "$actual_fingerprint" != "$fingerprint" || "$primary_count" != 1 ]]; then
  echo "La clé publique ne correspond pas à l'empreinte attendue." >&2
  exit 1
fi
# APT sur les anciennes versions de Debian attend un trousseau binaire.
if LC_ALL=C grep -q '^-----BEGIN PGP' "$keyring"; then
  echo 'Fournissez un trousseau public binaire, non blindé ASCII.' >&2
  exit 1
fi

cp "$authority" "$work_dir/authority.gpg"
python3 - "$script_dir" "$work_dir" "$fingerprint" "$authority_fingerprint" "$project_uid" "$catalog_url" "$repo_host" <<'PY'
import json, pathlib, sys, urllib.parse
sys.path.insert(0, sys.argv[1])
from apt_trust_refresh import HOST, SAFE_UID, TrustError, verify_certificates
work = pathlib.Path(sys.argv[2])
project_fpr, authority_fpr, uid, url, repo_host = sys.argv[3:]
try:
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.hostname != repo_host or parsed.username or parsed.password
            or parsed.fragment or not HOST.fullmatch(parsed.hostname) or not HOST.fullmatch(repo_host)
            or not SAFE_UID.fullmatch(uid)):
        raise TrustError('configuration du dépôt invalide')
    filtered, _, keys, _ = verify_certificates((work / 'authority.gpg').read_bytes(), b'',
                                                (work / 'public-keyring.gpg').read_bytes(),
                                                authority_fpr, uid)
    if keys != [project_fpr]:
        raise TrustError('la clé du projet ne correspond pas à la certification')
    (work / 'initial.gpg').write_bytes(filtered)
    (work / 'config.json').write_text(json.dumps({'authority_fingerprint': authority_fpr,
        'project_uid': uid, 'catalog_url': url, 'repo_host': repo_host}) + '\n')
except (OSError, ValueError, TrustError) as exc:
    print('Impossible de préparer le paquet de clés : {}'.format(exc), file=sys.stderr)
    sys.exit(1)
PY

install -d "$work_dir/package/DEBIAN" "$work_dir/package/usr/share/keyrings" \
  "$work_dir/package/usr/share/myeasytoolkit-archive-keyring" \
  "$work_dir/package/usr/lib/myeasytoolkit-archive-keyring" \
  "$work_dir/package/etc/apt/apt.conf.d" "$work_dir/package/etc/apt/preferences.d"
install -m 644 "$work_dir/initial.gpg" "$work_dir/package/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg"
install -m 644 "$work_dir/authority.gpg" "$work_dir/config.json" "$work_dir/package/usr/share/myeasytoolkit-archive-keyring/"
install -m 755 "$script_dir/apt_trust_refresh.py" "$script_dir/apt_trust_guard.py" "$work_dir/package/usr/lib/myeasytoolkit-archive-keyring/"
cat > "$work_dir/package/etc/apt/apt.conf.d/80myeasytoolkit-trust" <<'APTCONF'
APT::Update::Pre-Invoke { "/usr/lib/myeasytoolkit-archive-keyring/apt_trust_refresh.py"; };
DPkg::Pre-Install-Pkgs { "/usr/lib/myeasytoolkit-archive-keyring/apt_trust_guard.py"; };
DPkg::Tools::Options::/usr/lib/myeasytoolkit-archive-keyring/apt_trust_guard.py::Version "2";
APTCONF
cat > "$work_dir/package/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -eu
case "$1" in
  remove|purge) rm -f /etc/apt/preferences.d/99myeasytoolkit-block ;;
esac
POSTRM
chmod 755 "$work_dir/package/DEBIAN/postrm"
cat > "$work_dir/package/DEBIAN/control" <<CONTROL
Package: myeasytoolkit-archive-keyring
Version: $version
Section: misc
Priority: optional
Architecture: all
Maintainer: MyEasyToolkit
Depends: python3, gnupg, ca-certificates
Description: Public signing keys for the MyEasyToolkit APT repository
 Public OpenPGP keyring used to authenticate the MyEasyToolkit APT repository.
CONTROL
mkdir -p dist/keyring
dpkg-deb -Zxz --build --root-owner-group "$work_dir/package" "dist/keyring/myeasytoolkit-archive-keyring_${version}_all.deb"

#!/usr/bin/env bash
set -euo pipefail

# Runs only inside the disposable container started by tests/apt-maintenance.sh.
test -f /.dockerenv
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y --no-install-recommends apt-utils ca-certificates curl dpkg-dev gnupg openssl python3
ln -s /source/packaging packaging
ln -s /source/installers installers

work="$(mktemp -d)"
export GNUPGHOME="$work/gnupg"
install -d -m 0700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'MyEasyToolkit Fixture' ed25519 cert 1d
primary="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" {print $10; exit}')"
for index in 0 1 2; do
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$primary" ed25519 sign 1d
  mapfile -t subkeys < <(gpg --batch --with-colons --with-subkey-fingerprint --list-keys |
    awk -F: '$1=="sub" {subkey=1; next} $1=="fpr" && subkey {print $10; subkey=0}')
  # GPG keeps its own ordering. Export this generation by index.
  gpg --batch --export "${subkeys[$index]}!" > "$work/key-$index.gpg"
done
test "${subkeys[0]}" != "${subkeys[2]}"

name=myeasytoolkit
ring=myeasytoolkit-archive-keyring
key="/usr/share/keyrings/$ring.gpg"
source="/etc/apt/sources.list.d/$name.list"
host=packages.myeasytoolkit.com
archive="/var/cache/apt/archives/${name}_1.2.3_$(dpkg --print-architecture).deb"
payload="$work/payload"
inputs="$work/inputs"
mkdir "$inputs"
install -d "$payload/DEBIAN" "$payload/usr/bin" "$payload/usr/share/doc/$name"
cat > "$payload/usr/bin/$name" <<'CLI'
#!/bin/sh
case "$1" in
  --version) echo 'myeasytoolkit 1.2.3' ;;
  --help) echo 'Usage : myeasytoolkit [URL_DU_DEPOT]' ;;
  *) exit 1 ;;
esac
CLI
chmod 755 "$payload/usr/bin/$name"
printf 'Documentation MyEasyToolkit de test\n' > "$payload/usr/share/doc/$name/README.md"
(cd "$payload" && md5sum usr/bin/myeasytoolkit usr/share/doc/myeasytoolkit/README.md > DEBIAN/md5sums)
for arch in amd64 arm64; do
  printf 'Package: %s\nVersion: 1.2.3\nArchitecture: %s\nMaintainer: Test\nDepends: bash, ca-certificates, libc6\nDescription: Fixture\n' "$name" "$arch" > "$payload/DEBIAN/control"
  dpkg-deb --build --root-owner-group "$payload" "$inputs/${name}_1.2.3_$arch.deb"
done
for platform in darwin linux windows; do
  for arch in amd64 arm64; do
    case "$platform" in windows) ext=exe ;; *) ext=tar.gz ;; esac
    touch "$inputs/$name-$platform-$arch.$ext"
  done
done

export MET_APT_SIGNING_SUBKEY="${subkeys[2]}"
bash packaging/stage-release.sh "$inputs" "$work/dist" "$primary" "$work/key-2.gpg" "$primary" 3.0
for script in "$work/dist/install.sh" "$work/dist/releases/"*.sh; do
  bash -n "$script"
done
install -d "$work/tls"
openssl req -new -newkey rsa:2048 -nodes -x509 -days 1 -subj "/CN=$host" \
  -addext "subjectAltName=DNS:$host" -keyout "$work/tls/key" -out "/usr/local/share/ca-certificates/met-fixture.crt" 2>/dev/null
update-ca-certificates >/dev/null
printf '127.0.0.1 %s\n' "$host" >> /etc/hosts
python3 - "$work" <<'PY' &
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
import sys

work = Path(sys.argv[1])
server = ThreadingHTTPServer(('127.0.0.1', 443), partial(SimpleHTTPRequestHandler, directory=work / 'dist'))
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain('/usr/local/share/ca-certificates/met-fixture.crt', work / 'tls/key')
server.socket = tls.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
server=$!
trap 'kill "$server"; rm -rf "$work"' EXIT
for _ in {1..20}; do
  if curl -fsS "https://$host/apt/$ring.gpg" -o /dev/null; then break; fi
  sleep 0.25
done

install_script="$work/dist/install.sh"
repair_script="$work/dist/releases/repair.sh"
uninstall_script="$work/dist/releases/uninstall.sh"
cp "$work/key-0.gpg" "$key"
printf 'deb [signed-by=%s] https://%s/apt stable main\n' "$key" "$host" > "$source"
if apt-get -o "Dir::Etc::sourcelist=$source" -o Dir::Etc::sourceparts=- -o APT::Update::Error-Mode=any update; then
  echo 'La fixture devait reproduire une sous-clé manquante.' >&2
  exit 1
fi
bash "$install_script"
myeasytoolkit --version
dpkg-query -W "$ring"
cmp "$key" "$work/key-2.gpg"

# A source missing as well as an unreadable, obsolete or unknown key.
for old in missing unreadable corrupt previous; do
  rm -f "$source" "$key"
  case "$old" in
    unreadable) cp "$work/key-1.gpg" "$key"; chmod 000 "$key" ;;
    corrupt) printf 'corrompu' > "$key" ;;
    previous) cp "$work/key-1.gpg" "$key" ;;
  esac
  bash "$install_script"
  cmp "$key" "$work/key-2.gpg"
  test -s "$source"
done

# Check cryptographic rejection before touching the installed ring.
expect_failure() {
  if "$@"; then echo "Échec attendu : $*" >&2; exit 1; fi
}
cp "$work/dist/apt/$ring.gpg" "$work/public.gpg"
cp "$work/key-1.gpg" "$work/dist/apt/$ring.gpg"
expect_failure bash "$install_script"
cmp "$key" "$work/public.gpg"
cp "$work/public.gpg" "$work/dist/apt/$ring.gpg"
release="$work/dist/apt/dists/stable/InRelease"
cp "$release" "$work/InRelease"
sed 's/^Date:.*/Date: Sat, 01 Jan 2000 00:00:00 +0000/' "${release%/*}/Release" > "$work/old-release"
gpg --batch --yes --local-user "${subkeys[2]}!" --output "$release" --clearsign "$work/old-release"
expect_failure bash "$install_script"
cmp "$key" "$work/public.gpg"
cp "$work/InRelease" "$release"

# A valid signature by a different subkey under the same primary is refused.
gpg --batch --yes --local-user "${subkeys[1]}!" --output "$release" --clearsign "${release%/*}/Release"
expect_failure bash "$install_script"
cmp "$key" "$work/public.gpg"
cp "$work/InRelease" "$release"

# Sharing through a symbolic alias or a hard link protects the target.
ln -s "$key" /etc/apt/met-shared.gpg
foreign=/etc/apt/sources.list.d/foreign.sources
printf 'Types: deb\nURIs: https://fixture.invalid/apt\nSuites: stable\nComponents: main\nSigned-By:\n /etc/apt/met-shared.gpg\n' > "$foreign"
expect_failure bash "$install_script"
expect_failure bash "$uninstall_script"
cmp "$key" "$work/public.gpg"
rm "$foreign" /etc/apt/met-shared.gpg
ln "$key" /etc/apt/met-hardlink.gpg
expect_failure bash "$repair_script"
expect_failure bash "$uninstall_script"
rm /etc/apt/met-hardlink.gpg

# The exact same version and the project data survive repair.
mkdir -p /var/lib/myeasytoolkit
printf 'données de la fixture\n' > /var/lib/myeasytoolkit/user-data
package="$inputs/${name}_1.2.3_$(dpkg --print-architecture).deb"
dpkg --unpack "$package"
printf 'corrompu\n' > /usr/bin/myeasytoolkit
rm -f "/usr/share/doc/$name/README.md"
bash "$repair_script"
cmp /usr/bin/myeasytoolkit "$payload/usr/bin/myeasytoolkit"
test "$(myeasytoolkit --version)" = 'myeasytoolkit 1.2.3'

# Earlier packages lack checksum metadata. The signed archive supplies it.
rm "/var/lib/dpkg/info/$name.md5sums"
chmod 644 /usr/bin/myeasytoolkit
bash "$repair_script"
test -x /usr/bin/myeasytoolkit
test -s "/var/lib/dpkg/info/$name.md5sums"

# Minimal images may deliberately omit the packaged README.
filter=/etc/dpkg/dpkg.cfg.d/90-myeasytoolkit-fixture
printf 'path-exclude=/usr/share/doc/myeasytoolkit/README.md\n' > "$filter"
bash "$install_script"
test ! -e "/usr/share/doc/$name/README.md"
bash "$repair_script"
rm "$filter"

# A ring installed before the rotation may need upgrading during repair.
bash packaging/build-archive-keyring-deb.sh "$work/key-1.gpg" "$primary" 2.0
dpkg -i dist/keyring/"${ring}_2.0_all.deb"
bash "$repair_script"
test "$(dpkg-query -W -f='${Version}' "$ring")" = 3.0

# A failure after the package write restores the original APT files.
cp "$work/key-0.gpg" "$key"
rm "$source"
cp "$work/key-0.gpg" "$work/previous"
python3 - "$work" "$primary" "${subkeys[2]}" <<'PY'
import importlib.util
from pathlib import Path
import subprocess
import sys

work = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('maint', '/source/installers/apt-maintenance.py')
maint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maint)
run = maint.run
def fail_on_system_update(*args, **kwargs):
    if args[0] == 'apt-get' and f'Dir::State::lists={maint.LISTS}' in args and 'update' in args:
        raise RuntimeError('fixture de rollback')
    return run(*args, **kwargs)
maint.run = fail_on_system_update
try:
    maint.maintain('install', 'https://packages.myeasytoolkit.com', *sys.argv[2:],
                   maint.digest(work / 'public.gpg'), subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip())
except RuntimeError as error:
    assert str(error) == 'fixture de rollback', error
else:
    raise AssertionError('L’échec simulé devait interrompre l’installation.')
assert not maint.SOURCE.exists()
assert maint.KEY.read_bytes() == (work / 'previous').read_bytes()

# An exact or nested bind mount on a package path blocks cleanup.
mounts = maint.mounts
maint.mounts = lambda: mounts() | {maint.KEY}
try:
    maint.residual_plan('https://packages.myeasytoolkit.com/apt', {})
except RuntimeError as error:
    assert 'Point de montage' in str(error), error
else:
    raise AssertionError('Un fichier monté doit être préservé.')
PY
bash "$install_script"

# Both prompts use the controlling terminal, even for a streamed launcher.
uninstall() {
  printf '%s\n%s\n' "$1" "$2" | script -qefc "cat '$uninstall_script' | bash" /dev/null
}
uninstall OUI NON
test -s "$source"
test -s "$key"
test -x /usr/bin/myeasytoolkit
expect_failure bash "$uninstall_script"
test -s "$source"

# Stop dpkg after the first confirmation pair, then resume the journal.
printf '#!/bin/sh\nexit 5\n' > "/var/lib/dpkg/info/$name.postrm"
chmod 755 "/var/lib/dpkg/info/$name.postrm"
expect_failure uninstall OUI PURGER
test -s /var/lib/myeasytoolkit-apt-removal.json
expect_failure bash "$install_script"
rm "/var/lib/dpkg/info/$name.postrm"
uninstall OUI PURGER
test ! -e /var/lib/myeasytoolkit-apt-removal.json
test ! -e "$source"
test ! -e "$key"
test ! -e /usr/bin/myeasytoolkit
test -s /var/lib/myeasytoolkit/user-data

# Remove recognised orphans without either package, retaining user data and
# an unrelated file with a similar cache name.
cp "$work/key-0.gpg" "$key"
printf 'deb [signed-by=%s] https://%s/apt stable main\n' "$key" "$host" > "$source"
install -D "$payload/usr/bin/$name" "/usr/bin/$name"
install -D -m 644 "$payload/usr/share/doc/$name/README.md" "/usr/share/doc/$name/README.md"
cp "$package" "$archive"
touch /var/cache/apt/archives/myeasytoolkit-unrelated_1_arm64.deb
uninstall OUI PURGER
for file in "$source" "$key" "/usr/bin/$name" "/usr/share/doc/$name/README.md" "$archive"; do
  test ! -e "$file"
done
test -s /var/lib/myeasytoolkit/user-data
test -f /var/cache/apt/archives/myeasytoolkit-unrelated_1_arm64.deb
echo 'Les trois parcours APT et leur reprise sont vérifiés.'

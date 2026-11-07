#!/usr/bin/env bash
set -euo pipefail
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/fixture" "$work_dir/payload" "$work_dir/home"
cat > "$work_dir/bin/uname" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == '-s' ]]; then echo "${TEST_OS:-Darwin}"; else echo arm64; fi
MOCK
cat > "$work_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url=''
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
cp "$FIXTURE/${url##*/}" "$out"
MOCK
chmod +x "$work_dir/bin/uname" "$work_dir/bin/curl"
printf '#!/usr/bin/env bash\nprintf "installed\\n"\n' > "$work_dir/payload/myeasytoolkit"
tar -czf "$work_dir/fixture/myeasytoolkit-darwin-arm64.tar.gz" -C "$work_dir/payload" myeasytoolkit
sha256sum "$work_dir/fixture/myeasytoolkit-darwin-arm64.tar.gz" > "$work_dir/fixture/myeasytoolkit-darwin-arm64.tar.gz.sha256"
export FIXTURE="$work_dir/fixture" MET_INSTALL_DIR="$work_dir/home/.local/bin" PATH="$work_dir/bin:$PATH"
bash installers/install.sh
[[ "$("$MET_INSTALL_DIR/myeasytoolkit")" == installed ]]
printf 'wrong checksum\n' > "$FIXTURE/myeasytoolkit-darwin-arm64.tar.gz.sha256"
if bash installers/install.sh; then
  echo 'Une somme de contrôle invalide aurait dû faire échouer l installation.' >&2
  exit 1
fi

# Exécuter la branche APT sans modifier le système : les commandes privilégiées
# et le téléchargement de la clé sont remplacés par des fixtures locales.
cat > "$work_dir/bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == --print-architecture ]]
printf '%s\n' "$TEST_APT_ARCH"
MOCK
cat > "$work_dir/bin/gpg" <<'MOCK'
#!/usr/bin/env bash
printf 'pub:::::::::\nfpr:::::::::%s:\n' "$TEST_FINGERPRINT"
MOCK
cat > "$work_dir/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
exec "$@"
MOCK
cat > "$work_dir/bin/install" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == -m && "$2" == 644 ]]
case "$4" in
  /etc/apt/sources.list.d/myeasytoolkit.list) cp "$3" "$TEST_OUTPUT" ;;
  /usr/share/keyrings/myeasytoolkit-archive-keyring.gpg) ;;
  *) exit 1 ;;
esac
MOCK
cat > "$work_dir/bin/apt-get" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_APT_CALLS"
MOCK
chmod +x "$work_dir/bin/dpkg" "$work_dir/bin/gpg" "$work_dir/bin/sudo" "$work_dir/bin/install" "$work_dir/bin/apt-get"
export TEST_OS=Linux TEST_FINGERPRINT=3DDACB1CAEC51E8466DB12456A0AFA48DB9C62D5
export TEST_OUTPUT="$work_dir/source.list" TEST_APT_CALLS="$work_dir/apt-calls"
printf 'test key\n' > "$FIXTURE/myeasytoolkit-archive-keyring.gpg"
sed "s/__APT_FINGERPRINT__/$TEST_FINGERPRINT/" installers/install.sh > "$work_dir/install.sh"
for TEST_APT_ARCH in amd64 arm64; do
  export TEST_APT_ARCH
  : > "$TEST_APT_CALLS"
  bash "$work_dir/install.sh"
  grep -Fx "deb [arch=$TEST_APT_ARCH signed-by=/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg] https://packages.myeasytoolkit.com/apt stable main" "$TEST_OUTPUT"
  grep -Fx 'update' "$TEST_APT_CALLS"
  grep -Fx 'install -y myeasytoolkit' "$TEST_APT_CALLS"
done
TEST_APT_ARCH=i386
export TEST_APT_ARCH
: > "$TEST_APT_CALLS"
if bash "$work_dir/install.sh"; then
  echo 'Une architecture Debian non prise en charge aurait dû être refusée.' >&2
  exit 1
fi
[[ ! -s "$TEST_APT_CALLS" ]]

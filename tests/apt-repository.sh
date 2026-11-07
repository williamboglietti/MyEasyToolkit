#!/usr/bin/env bash
set -euo pipefail
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
chmod 755 "$work_dir"
export GNUPGHOME="$work_dir/gnupg"
mkdir -m 700 "$GNUPGHOME"
printf 'ephemeral-test-passphrase' > "$work_dir/passphrase"
chmod 600 "$work_dir/passphrase"
export MET_GPG_PASSPHRASE_FILE="$work_dir/passphrase"
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-generate-key 'MyEasyToolkit CI <ci@example.invalid>' ed25519 sign 1d
fingerprint="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
bash packaging/build-apt-repository.sh dist "$work_dir/repo" "$fingerprint"
gpgv --keyring "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo/dists/stable/InRelease"
arch="$(dpkg --print-architecture)"
case "$arch" in amd64|arm64) ;; *) echo "Architecture inattendue : $arch" >&2; exit 1 ;; esac
grep -qx 'Package: myeasytoolkit' "$work_dir/repo/dists/stable/main/binary-$arch/Packages"
mkdir -p "$work_dir/apt/lists/partial" "$work_dir/apt/cache/archives/partial"
update_test_apt() {
  LC_ALL=C apt-get \
    -o "Dir::Etc::sourcelist=$work_dir/sources.list" \
    -o Dir::Etc::sourceparts=- \
    -o "Dir::State::lists=$work_dir/apt/lists" \
    -o "Dir::Cache=$work_dir/apt/cache" \
    -o APT::Architectures::=i386 \
    -o APT::Get::List-Cleanup=0 update 2>&1
}
# Reproduire la notification multiarchitecture, puis vérifier qu'elle disparaît
# lorsque la source utilise le filtre fourni par l'installateur.
printf 'deb [signed-by=%s] file:%s stable main\n' "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo" > "$work_dir/sources.list"
update_test_apt | tee "$work_dir/apt-unrestricted.log"
grep -q 'binary-i386' "$work_dir/apt-unrestricted.log"
printf 'deb [arch=%s signed-by=%s] file:%s stable main\n' "$arch" "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo" > "$work_dir/sources.list"
update_test_apt | tee "$work_dir/apt-restricted.log"
if grep -q 'binary-i386' "$work_dir/apt-restricted.log"; then
  echo 'Le filtre de la source APT devrait ignorer i386.' >&2
  exit 1
fi

for file in myeasytoolkit-darwin-amd64.tar.gz myeasytoolkit-darwin-arm64.tar.gz myeasytoolkit-linux-amd64.tar.gz myeasytoolkit-linux-arm64.tar.gz myeasytoolkit-windows-amd64.exe myeasytoolkit-windows-arm64.exe; do
  printf 'fixture\n' > "dist/$file"
done
bash packaging/stage-release.sh dist "$work_dir/staged" "$fingerprint"
grep -q "$fingerprint" "$work_dir/staged/install.sh"
test -s "$work_dir/staged/apt/dists/stable/InRelease"
grep -q 'Content-Type: text/plain; charset=utf-8' "$work_dir/staged/_headers"
(cd "$work_dir/staged/releases/latest" && sha256sum -c ./*.sha256)

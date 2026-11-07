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
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-generate-key 'MyEasyToolkit CI <ci@example.invalid>' ed25519 cert 1d
fingerprint="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-add-key "$fingerprint" ed25519 sign 1d
# La CI de publication ne doit avoir besoin que de la sous-clé de signature.
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --export-secret-subkeys "$fingerprint" > "$work_dir/signing-subkey.gpg"
export GNUPGHOME="$work_dir/signing-only"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --import "$work_dir/signing-subkey.gpg"
gpg --batch --with-colons --list-secret-keys "$fingerprint" > "$work_dir/secret-key-info"
awk -F: '$1 == "sec" && $15 == "#" { primary_offline = 1 } $1 == "ssb" && $15 != "#" { subkey_available = 1 } END { exit !(primary_offline && subkey_available) }' "$work_dir/secret-key-info"
bash packaging/build-apt-repository.sh dist "$work_dir/repo" "$fingerprint"
gpgv --keyring "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo/dists/stable/InRelease"
gpgv --keyring "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo/dists/stable/Release.gpg" "$work_dir/repo/dists/stable/Release"
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
    -o "APT::Architectures::=$arch" \
    -o APT::Architectures::=i386 \
    -o APT::Get::List-Cleanup=0 update 2>&1
}
# Vérifier le dépôt signé avec une architecture étrangère configurée dans APT.
printf 'deb [arch=%s signed-by=%s] file:%s stable main\n' "$arch" "$work_dir/repo/myeasytoolkit-archive-keyring.gpg" "$work_dir/repo" > "$work_dir/sources.list"
update_test_apt | tee "$work_dir/apt-restricted.log"
if grep -q 'binary-i386' "$work_dir/apt-restricted.log"; then
  echo 'Le filtre de la source APT devrait ignorer i386.' >&2
  exit 1
fi

mkdir -p "$work_dir/release-input"
cp dist/*.deb "$work_dir/release-input/"
# Chaque job CI construit une architecture ; simuler l'autre pour préparer une publication complète.
if [[ "$arch" == amd64 ]]; then other_arch=arm64; else other_arch=amd64; fi
mkdir -p "$work_dir/other-package/DEBIAN"
package_version="$(dpkg-deb -f dist/*.deb Version)"
printf 'Package: myeasytoolkit\nVersion: %s\nArchitecture: %s\nMaintainer: Test\nDescription: Fixture\n' "$package_version" "$other_arch" > "$work_dir/other-package/DEBIAN/control"
dpkg-deb --build "$work_dir/other-package" "$work_dir/release-input/fixture-$other_arch.deb"
for file in myeasytoolkit-darwin-amd64.tar.gz myeasytoolkit-darwin-arm64.tar.gz myeasytoolkit-linux-amd64.tar.gz myeasytoolkit-linux-arm64.tar.gz myeasytoolkit-windows-amd64.exe myeasytoolkit-windows-arm64.exe; do
  printf 'fixture\n' > "$work_dir/release-input/$file"
done
bash packaging/stage-release.sh "$work_dir/release-input" "$work_dir/staged" "$fingerprint"
grep -q "$fingerprint" "$work_dir/staged/install.sh"
test -s "$work_dir/staged/apt/dists/stable/InRelease"
grep -q 'Content-Type: text/plain; charset=utf-8' "$work_dir/staged/_headers"
(cd "$work_dir/staged/releases/latest" && sha256sum -c ./*.sha256)
for test_arch in amd64 arm64; do
  package="$work_dir/staged/releases/latest/myeasytoolkit-linux-$test_arch.deb"
  gpgv --keyring "$work_dir/staged/apt/myeasytoolkit-archive-keyring.gpg" "$package.asc" "$package"
  [[ "$(dpkg-deb -f "$package" Architecture)" == "$test_arch" ]]
  matched=''
  for repository_package in "$work_dir/staged/apt/pool/main/m/myeasytoolkit/"*.deb; do
    if [[ "$(dpkg-deb -f "$repository_package" Architecture)" == "$test_arch" ]]; then
      cmp "$package" "$repository_package"
      matched=1
    fi
  done
  [[ "$matched" == 1 ]] || { echo "Paquet $test_arch absent du dépôt." >&2; exit 1; }
done
# Une modification après signature ne doit jamais être acceptée.
cp "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb" "$work_dir/tampered.deb"
printf 'tampering' >> "$work_dir/tampered.deb"
if gpgv --keyring "$work_dir/staged/apt/myeasytoolkit-archive-keyring.gpg" "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb.asc" "$work_dir/tampered.deb" >/dev/null 2>&1; then
  echo 'La signature devrait refuser un paquet modifié.' >&2
  exit 1
fi
mkdir -m 700 "$work_dir/wrong-key-home"
(
  export GNUPGHOME="$work_dir/wrong-key-home"
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'Untrusted CI <wrong@example.invalid>' ed25519 sign 1d
  gpg --batch --export > "$work_dir/wrong-key.gpg"
)
if gpgv --keyring "$work_dir/wrong-key.gpg" "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb.asc" "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb" >/dev/null 2>&1; then
  echo 'Une clé non approuvée ne doit pas valider le paquet.' >&2
  exit 1
fi
cp "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb" "$work_dir/release-input/duplicate.deb"
if bash packaging/stage-release.sh "$work_dir/release-input" "$work_dir/duplicate" "$fingerprint" >/dev/null 2>&1; then
  echo 'Une publication avec deux paquets pour la même architecture doit échouer.' >&2
  exit 1
fi

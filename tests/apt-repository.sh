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
if MET_APT_SUITE=testing bash packaging/build-apt-repository.sh dist "$work_dir/no-signer" "$fingerprint" >/dev/null 2>&1; then
  echo 'Le canal test doit exiger une sous-clé explicite.' >&2; exit 1
fi
if MET_APT_SIGNING_SUBKEY=0000000000000000000000000000000000000000 bash packaging/build-apt-repository.sh dist "$work_dir/wrong-subkey" "$fingerprint" >/dev/null 2>&1; then
  echo 'Une sous-clé absente doit être refusée.' >&2; exit 1
fi
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-generate-key 'MyEasyToolkit next CI <next@example.invalid>' ed25519 sign 1d
next_fingerprint="$(gpg --batch --with-colons --list-keys 'next@example.invalid' | awk -F: '$1 == "fpr" { print $10; exit }')"
gpg --batch --export "$fingerprint" "$next_fingerprint" > "$work_dir/rotation-keyring.gpg"
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --export-secret-keys "$next_fingerprint" > "$work_dir/next-signing-key.gpg"
# Le paquet de clés contient uniquement le certificat public attendu.
gpg --batch --export "$fingerprint" > "$work_dir/public-keyring.gpg"
gpg --batch --armor --export "$fingerprint" > "$work_dir/public-keyring.asc"
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --export-secret-keys "$fingerprint" > "$work_dir/private-keyring.gpg"
repo_dir="$PWD"
mkdir -p "$work_dir/keyring-build"
(
  cd "$work_dir/keyring-build"
  bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/public-keyring.gpg" "$fingerprint" 1.0
  keyring_deb=dist/keyring/myeasytoolkit-archive-keyring_1.0_all.deb
  [[ "$(dpkg-deb -f "$keyring_deb" Package)" == myeasytoolkit-archive-keyring ]]
  [[ "$(dpkg-deb -f "$keyring_deb" Architecture)" == all ]]
  dpkg-deb -x "$keyring_deb" extracted
  cmp "$work_dir/public-keyring.gpg" extracted/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg
  bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/rotation-keyring.gpg" "$fingerprint,$next_fingerprint" 1.1
  dpkg-deb -x dist/keyring/myeasytoolkit-archive-keyring_1.1_all.deb rotation
  cmp "$work_dir/rotation-keyring.gpg" rotation/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg
  if bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/rotation-keyring.gpg" "$fingerprint" 1.0 >/dev/null 2>&1; then
    echo 'Une clé non déclarée doit être refusée.' >&2; exit 1
  fi
  if bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/public-keyring.gpg" 0000000000000000000000000000000000000000 1.0 >/dev/null 2>&1; then
    echo 'Une empreinte incorrecte doit être refusée.' >&2
    exit 1
  fi
  if bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/private-keyring.gpg" "$fingerprint" 1.0 >/dev/null 2>&1; then
    echo 'Une clé privée ne doit jamais être incluse dans le paquet.' >&2
    exit 1
  fi
  if bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/public-keyring.asc" "$fingerprint" 1.0 >/dev/null 2>&1; then
    echo 'Un trousseau ASCII doit être refusé pour garantir la compatibilité APT.' >&2
    exit 1
  fi
)
# La CI de publication ne doit avoir besoin que de la sous-clé de signature.
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --export-secret-subkeys "$fingerprint" > "$work_dir/signing-subkey.gpg"
cat "$work_dir/public-keyring.gpg" "$work_dir/signing-subkey.gpg" > "$work_dir/mixed-keyring.gpg"
(
  cd "$work_dir/keyring-build"
  if bash "$repo_dir/packaging/build-archive-keyring-deb.sh" "$work_dir/mixed-keyring.gpg" "$fingerprint" 1.0 >/dev/null 2>&1; then
    echo 'Un trousseau public contenant une sous-clé privée doit être refusé.' >&2
    exit 1
  fi
)
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
for test_arch in amd64 arm64; do
  grep -qx 'Package: myeasytoolkit-archive-keyring' "$work_dir/staged/apt/dists/stable/main/binary-$test_arch/Packages"
done
keyring_package=("$work_dir/staged/apt/pool/main/m/myeasytoolkit-archive-keyring/"*.deb)
[[ ${#keyring_package[@]} -eq 1 ]]
mkdir -p "$work_dir/keyring-control"
dpkg-deb -e "${keyring_package[0]}" "$work_dir/keyring-control"
[[ ! -f "$work_dir/keyring-control/postinst" && ! -f "$work_dir/keyring-control/preinst" ]]
if dpkg-deb -c "${keyring_package[0]}" | grep -q '/etc/apt/'; then
  echo 'Le paquet de clés ne doit pas installer de configuration APT.' >&2; exit 1
fi
bash packaging/stage-release.sh "$work_dir/release-input" "$work_dir/staged-rotation" "$fingerprint" "$work_dir/rotation-keyring.gpg" "$fingerprint,$next_fingerprint" 1.1
rotation_package=("$work_dir/staged-rotation/apt/pool/main/m/myeasytoolkit-archive-keyring/"*.deb)
dpkg-deb -x "${rotation_package[0]}" "$work_dir/staged-keyring"
cmp "$work_dir/rotation-keyring.gpg" "$work_dir/staged-keyring/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg"
# Une machine ayant reçu le trousseau transitoire accepte la nouvelle clé ;
# une machine qui ne connaît que l'ancienne ne doit pas l'accepter.
gpg --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --import "$work_dir/next-signing-key.gpg"
bash packaging/build-apt-repository.sh "$work_dir/release-input" "$work_dir/new-repo" "$next_fingerprint" "${rotation_package[0]}"
printf 'deb [arch=%s signed-by=%s] file:%s stable main\n' "$arch" "$work_dir/public-keyring.gpg" "$work_dir/new-repo" > "$work_dir/sources.list"
if update_test_apt > "$work_dir/old-key.log" 2>&1 && ! grep -q 'NO_PUBKEY' "$work_dir/old-key.log"; then
  echo 'La nouvelle signature ne doit pas être acceptée avec la seule ancienne clé.' >&2; exit 1
fi
grep -q 'NO_PUBKEY' "$work_dir/old-key.log"
printf 'deb [arch=%s signed-by=%s] file:%s stable main\n' "$arch" "$work_dir/rotation-keyring.gpg" "$work_dir/new-repo" > "$work_dir/sources.list"
update_test_apt > "$work_dir/rotation-update.log" 2>&1
if grep -q 'NO_PUBKEY' "$work_dir/rotation-update.log"; then
  echo 'Le trousseau de transition doit accepter la nouvelle signature.' >&2; exit 1
fi
grep -q "$fingerprint" "$work_dir/staged/install.sh"
if grep -q '__APT_SIGNER_FINGERPRINT__' "$work_dir/staged/install.sh"; then
  echo "Le signataire précis doit être incorporé à l'installateur." >&2; exit 1
fi
bootstrap_signer="$(gpgv --status-fd 1 --keyring "$work_dir/staged/apt/myeasytoolkit-archive-keyring.gpg" "$work_dir/staged/apt/dists/stable/InRelease" 2>/dev/null | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3 }')"
bootstrap_subkeys="$(gpg --batch --with-colons --with-subkey-fingerprint --show-keys "$work_dir/staged/apt/myeasytoolkit-archive-keyring.gpg" | awk -F: '$1 == "sub" {s=1;next} s && $1 == "fpr" {print $10;s=0}')"
[[ "$bootstrap_subkeys" == "$bootstrap_signer" ]]
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
# Une CI contenant aussi des sous-clés de test ne doit jamais les inclure dans
# le trousseau stable ; une rotation peut autoriser une autre sous-clé stable.
gpg --homedir "$work_dir/gnupg" --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-add-key "$fingerprint" ed25519 sign 1d
gpg --homedir "$work_dir/gnupg" --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --quick-add-key "$fingerprint" ed25519 sign 1d
mapfile -t subs < <(gpg --homedir "$work_dir/gnupg" --batch --with-colons --with-subkey-fingerprint --list-keys "$fingerprint" | awk -F: '$1 == "sub" { next_fpr=1; next } next_fpr && $1 == "fpr" { print $10; next_fpr=0 }')
[[ ${#subs[@]} -eq 3 ]]
gpg --homedir "$work_dir/gnupg" --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --export-secret-subkeys "$fingerprint" > "$work_dir/all-subkeys.gpg"
mkdir -m 700 "$work_dir/all-signers"
gpg --homedir "$work_dir/all-signers" --batch --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" --import "$work_dir/all-subkeys.gpg"
MET_APT_SIGNING_SUBKEY="${subs[0]}" MET_APT_ALLOWED_SUBKEYS="${subs[0]},${subs[2]}" GNUPGHOME="$work_dir/all-signers" \
  bash packaging/stage-release.sh "$work_dir/release-input" "$work_dir/staged-filtered" "$fingerprint"
filtered_package=("$work_dir/staged-filtered/apt/pool/main/m/myeasytoolkit-archive-keyring/"*.deb)
dpkg-deb -x "${filtered_package[0]}" "$work_dir/filtered-keyring"
gpg --batch --with-colons --with-subkey-fingerprint --show-keys "$work_dir/filtered-keyring/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg" |
  awk -F: '$1 == "sub" { next_fpr=1; next } next_fpr && $1 == "fpr" { print $10; next_fpr=0 }' | sort > "$work_dir/filtered-subkeys"
printf '%s\n' "${subs[0]}" "${subs[2]}" | sort > "$work_dir/expected-subkeys"
cmp "$work_dir/filtered-subkeys" "$work_dir/expected-subkeys"
bootstrap_subkeys="$(gpg --batch --with-colons --with-subkey-fingerprint --show-keys "$work_dir/staged-filtered/apt/myeasytoolkit-archive-keyring.gpg" | awk -F: '$1 == "sub" {s=1;next} s && $1 == "fpr" {print $10;s=0}')"
[[ "$bootstrap_subkeys" == "${subs[0]}" ]]
printf 'Test de signature non autorisée\n' > "$work_dir/test-release"
gpg --homedir "$work_dir/all-signers" --batch --yes --pinentry-mode loopback --passphrase-file "$MET_GPG_PASSPHRASE_FILE" \
  --local-user "${subs[1]}!" --output "$work_dir/test-release.sig" --detach-sign "$work_dir/test-release"
if gpgv --keyring "$work_dir/filtered-keyring/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg" "$work_dir/test-release.sig" "$work_dir/test-release" >/dev/null 2>&1; then
  echo 'Une sous-clé de test ne doit pas être acceptée par le trousseau stable.' >&2; exit 1
fi
cp "$work_dir/staged/releases/latest/myeasytoolkit-linux-$arch.deb" "$work_dir/release-input/duplicate.deb"
if bash packaging/stage-release.sh "$work_dir/release-input" "$work_dir/duplicate" "$fingerprint" >/dev/null 2>&1; then
  echo 'Une publication avec deux paquets pour la même architecture doit échouer.' >&2
  exit 1
fi

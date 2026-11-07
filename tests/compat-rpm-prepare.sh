#!/usr/bin/env bash
set -euo pipefail

dnf install -y rpm-build rpm-sign gnupg2 xz
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
chmod 700 "$GNUPGHOME"
trap 'gpgconf --kill gpg-agent || true; rm -rf "$GNUPGHOME"' EXIT
mkdir -p /tmp/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cat > /tmp/rpmbuild/SPECS/met-compat.spec <<'SPEC'
Name: met-compat-test
Version: 1
Release: 1
Summary: Temporary package for signature compatibility tests
License: MIT
BuildArch: noarch

%description
Temporary package for signature compatibility tests.

%install
mkdir -p %{buildroot}/usr/share/met-compat
printf 'fixture\n' > %{buildroot}/usr/share/met-compat/fixture

%files
/usr/share/met-compat/fixture
SPEC
rpmbuild -bb --define '_topdir /tmp/rpmbuild' --define '_binary_payload w9.xzdio' /tmp/rpmbuild/SPECS/met-compat.spec
for algo in ed25519 rsa4096; do
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "CI $algo <test@example.invalid>" "$algo" cert 1d
  fingerprint="$(gpg --batch --with-colons --list-keys "CI $algo" | awk -F: '$1 == "fpr" {print $10; exit}')"
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-add-key "$fingerprint" "$algo" sign 1d
  gpg --batch --armor --export "$fingerprint" > "/fixtures/$algo.asc"
  cp /tmp/rpmbuild/RPMS/noarch/met-compat-test-1-1.noarch.rpm "/fixtures/$algo.rpm"
  rpmsign --define "_gpg_name $fingerprint" --addsign "/fixtures/$algo.rpm"
done
chmod -R a+rX /fixtures

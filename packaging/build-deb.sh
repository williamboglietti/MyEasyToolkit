#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
  echo 'La construction du paquet Debian doit être effectuée sous Linux.' >&2
  exit 1
fi
if [[ $# -gt 0 ]]; then
  version="$1"
else
  package_id="$(cargo pkgid --locked)"
  version="${package_id##*#}"
  version="${version##*@}"
fi
if ! dpkg --validate-version "$version"; then
  echo 'Version Debian invalide.' >&2
  exit 1
fi
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Architecture non prise en charge.' >&2; exit 1 ;;
esac
target="${TARGET:-}"
if [[ -n "$target" ]]; then
  cargo build --release --locked --target "$target"
  binary="target/$target/release/myeasytoolkit"
else
  cargo build --release --locked
  binary="target/release/myeasytoolkit"
fi
package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT
install -d "$package_dir/DEBIAN" "$package_dir/usr/bin" "$package_dir/usr/share/doc/myeasytoolkit"
install -m 755 "$binary" "$package_dir/usr/bin/myeasytoolkit"
install -m 644 README.md "$package_dir/usr/share/doc/myeasytoolkit/README.md"
cat > "$package_dir/DEBIAN/control" <<CONTROL
Package: myeasytoolkit
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: MyEasyToolkit
Depends: libc6, ca-certificates, bash
Description: Browse and run scripts from HTTP repositories
 Interactive terminal browser for public and authenticated script repositories.
CONTROL
mkdir -p dist
# zstd, the default on recent dpkg versions, cannot be read by Debian 10/11.
dpkg-deb -Zxz --build --root-owner-group "$package_dir" "dist/myeasytoolkit_${version}_${arch}.deb"

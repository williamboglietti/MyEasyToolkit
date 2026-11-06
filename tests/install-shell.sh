#!/usr/bin/env bash
set -euo pipefail
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/fixture" "$work_dir/payload" "$work_dir/home"
cat > "$work_dir/bin/uname" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == '-s' ]]; then echo Darwin; else echo arm64; fi
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
export FIXTURE="$work_dir/fixture" HOME="$work_dir/home" PATH="$work_dir/bin:$PATH"
bash installers/install.sh
[[ "$("$HOME/.local/bin/myeasytoolkit")" == installed ]]
printf 'wrong checksum\n' > "$FIXTURE/myeasytoolkit-darwin-arm64.tar.gz.sha256"
if bash installers/install.sh; then
  echo 'Une somme de contrôle invalide aurait dû faire échouer l installation.' >&2
  exit 1
fi

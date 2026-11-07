#!/usr/bin/env bash
set -euo pipefail

revision='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
other='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
script='packaging/validate-release-revision.sh'
actual="$(RELEASE_REVISION="$revision" MAIN_REVISION="$revision" SUCCESSFUL_CI_COUNT=1 bash "$script")"
[[ "$actual" == "$revision" ]]
if RELEASE_REVISION="$revision" MAIN_REVISION="$other" SUCCESSFUL_CI_COUNT=1 bash "$script" >/dev/null 2>&1; then
  echo 'Une ancienne révision ne doit pas être publiée.' >&2
  exit 1
fi
if RELEASE_REVISION="$revision" MAIN_REVISION="$revision" SUCCESSFUL_CI_COUNT=0 bash "$script" >/dev/null 2>&1; then
  echo 'Une révision sans CI verte ne doit pas être publiée.' >&2
  exit 1
fi
if RELEASE_REVISION='invalid' MAIN_REVISION='invalid' SUCCESSFUL_CI_COUNT=1 bash "$script" >/dev/null 2>&1; then
  echo 'Une révision invalide ne doit pas être publiée.' >&2
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

# The caller obtains MAIN_REVISION and SUCCESSFUL_CI_COUNT from GitHub's API.
: "${RELEASE_REVISION:?Missing release revision}"
: "${MAIN_REVISION:?Missing main revision}"
: "${SUCCESSFUL_CI_COUNT:?Missing successful CI count}"

if [[ ! "$RELEASE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Révision de publication invalide.' >&2
  exit 1
fi
if [[ "$RELEASE_REVISION" != "$MAIN_REVISION" ]]; then
  echo 'La révision validée ne correspond plus à la tête de main.' >&2
  exit 1
fi
if [[ ! "$SUCCESSFUL_CI_COUNT" =~ ^[0-9]+$ ]] || (( SUCCESSFUL_CI_COUNT == 0 )); then
  echo 'Aucune CI verte sur ce commit de main.' >&2
  exit 1
fi
printf '%s\n' "$RELEASE_REVISION"

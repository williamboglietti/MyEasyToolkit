#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker run --rm --init -v "$repo:/source:ro" -w /tmp debian:12 bash /source/tests/fixtures/apt-maintenance.sh

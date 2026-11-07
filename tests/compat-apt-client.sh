#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
if [[ -f /etc/debian_version ]] && [[ "$(cut -d. -f1 /etc/debian_version)" == 10 ]]; then
  # Debian 10 has moved to the signed Debian archive.
  printf 'deb http://archive.debian.org/debian buster main\n' > /etc/apt/sources.list
  apt-get -o Acquire::Check-Valid-Until=false update
else
  apt-get update
fi
apt-get install -y --no-install-recommends ca-certificates

arch="$(dpkg --print-architecture)"
for algo in ed25519 rsa4096; do
  source_list="/tmp/met-$algo.list"
  printf 'deb [arch=%s signed-by=/fixtures/%s.gpg] file:/fixtures/%s stable main\n' "$arch" "$algo" "$algo" > "$source_list"
  apt_args=(-o "Dir::Etc::sourcelist=$source_list" -o Dir::Etc::sourceparts=-)
  apt-get "${apt_args[@]}" update
  if dpkg-query -W -f='${Status}' myeasytoolkit 2>/dev/null | grep -q 'install ok installed'; then
    apt-get "${apt_args[@]}" install -y --reinstall myeasytoolkit
  else
    apt-get "${apt_args[@]}" install -y myeasytoolkit
  fi
  myeasytoolkit --version
  if [[ "$algo" == ed25519 ]]; then wrong=rsa4096; else wrong=ed25519; fi
  if gpgv --keyring "/fixtures/$wrong.gpg" "/fixtures/$algo/dists/stable/InRelease"; then
    echo 'Une signature a été acceptée avec une mauvaise clé.' >&2
    exit 1
  fi
  echo "Signature $algo, paquet et refus de la mauvaise clé : OK"
done

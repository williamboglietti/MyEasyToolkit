#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
debian_version="$(cut -d. -f1 /etc/debian_version)"
if [[ "$debian_version" == 10 || "$debian_version" == 11 ]]; then
  # Use the signed archive for old releases and allow archived Release dates.
  if [[ "$debian_version" == 10 ]]; then suite=buster; else suite=bullseye; fi
  printf 'deb http://archive.debian.org/debian %s main\n' "$suite" > /etc/apt/sources.list
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

# Les deux signatures appartiennent à la même clé principale. Chaque source
# épingle uniquement l'empreinte de sa sous-clé ; des listes neuves empêchent
# un index APT en cache de masquer un refus de signature.
mapfile -t channel_signers < /fixtures/channel-signers.txt
[[ ${#channel_signers[@]} -eq 2 ]]
for repo in stable testing; do
  for signer in stable testing; do
    if [[ "$signer" == stable ]]; then subkey="${channel_signers[0]}"; else subkey="${channel_signers[1]}"; fi
    met_test="$(mktemp -d /tmp/met-channel.XXXXXXXX)"
    chmod 755 "$met_test"
    mkdir -p "$met_test/lists/partial"
    printf 'deb [arch=%s signed-by=/fixtures/channels.gpg,%s!] file:/fixtures/channel-%s %s main\n' \
      "$arch" "$subkey" "$repo" "$repo" > "$met_test/source.list"
    if apt-get -o "Dir::Etc::sourcelist=$met_test/source.list" -o Dir::Etc::sourceparts=- \
      -o "Dir::State::lists=$met_test/lists" update > "$met_test/apt.log" 2>&1; then
      if [[ "$repo" != "$signer" ]]; then
        cat "$met_test/apt.log"
        echo "ERREUR : $repo a accepté la sous-clé $signer." >&2; exit 1
      fi
    else
      if [[ "$repo" == "$signer" ]]; then
        cat "$met_test/apt.log"
        echo "ERREUR : $repo a refusé sa propre sous-clé." >&2; exit 1
      fi
      grep -Eq 'NO_PUBKEY|not signed|signatures were invalid|signatures couldn.t be verified' "$met_test/apt.log" || { cat "$met_test/apt.log"; exit 1; }
    fi
    printf 'Dépôt %s, sous-clé %s : comportement attendu.\n' "$repo" "$signer"
    rm -rf "$met_test"
  done
done

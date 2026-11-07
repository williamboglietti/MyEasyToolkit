#!/usr/bin/env bash
set -euo pipefail

expected_ed25519="${1:?Indiquer supported ou unsupported}"
[[ "$expected_ed25519" == supported || "$expected_ed25519" == unsupported ]]
echo "Distribution : $(grep '^PRETTY_NAME=' /etc/os-release) ; $(rpm --version)"
for algo in rsa4096 ed25519; do
  log="/tmp/met-$algo.log"
  if rpm --import "/fixtures/$algo.asc" > "$log" 2>&1 &&
     rpm --checksig --verbose "/fixtures/$algo.rpm" >> "$log" 2>&1 &&
     grep -Eiq '(RSA|EdDSA|DSA).*Signature.*: OK' "$log"; then
    cat "$log"
    echo "Signature RPM $algo : vérifiée"
    if [[ "$algo" == ed25519 && "$expected_ed25519" == unsupported ]]; then
      echo 'Ed25519 est désormais pris en charge : actualiser le test de compatibilité.' >&2
      exit 1
    fi
  else
    cat "$log"
    if [[ "$algo" == rsa4096 ]]; then
      echo 'La signature RSA 4096 du paquet RPM ne peut pas être vérifiée.' >&2
      exit 1
    fi
    if [[ "$expected_ed25519" != unsupported ]] || ! grep -q 'key 1 import failed' "$log"; then
      echo 'Échec inattendu de la vérification Ed25519.' >&2
      exit 1
    fi
    # Rocky Linux 8's RPM cannot import this EdDSA key.
    echo "::warning::Signature RPM Ed25519 non vérifiée sur $(rpm --version) ; voir les détails ci-dessus."
  fi
done

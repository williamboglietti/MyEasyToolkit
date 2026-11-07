#!/usr/bin/env bash
set -euo pipefail

echo "Distribution : $(cat /etc/os-release | grep '^PRETTY_NAME=') ; $(rpm --version)"
for algo in rsa4096 ed25519; do
  log="/tmp/met-$algo.log"
  if rpm --import "/fixtures/$algo.asc" > "$log" 2>&1 &&
     rpm --checksig --verbose "/fixtures/$algo.rpm" >> "$log" 2>&1 &&
     grep -Eiq '(RSA|EdDSA|DSA).*Signature.*: OK' "$log"; then
    cat "$log"
    echo "Signature RPM $algo : vérifiée"
  else
    cat "$log"
    if [[ "$algo" == rsa4096 ]]; then
      echo 'La signature RSA 4096 du paquet RPM ne peut pas être vérifiée.' >&2
      exit 1
    fi
    # Older RPM releases do not implement EdDSA. Report the exact result
    # without treating an unsupported optional algorithm as RSA support.
    echo "::warning::Signature RPM Ed25519 non vérifiée sur $(rpm --version) ; voir les détails ci-dessus."
  fi
done

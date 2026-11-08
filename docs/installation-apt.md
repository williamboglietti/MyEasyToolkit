# Installation APT manuelle

Cette procédure concerne Debian et Ubuntu sur les architectures `amd64` et `arm64`. Elle nécessite que la version comprenant le paquet `myeasytoolkit-archive-keyring` ait été publiée ; sa préparation dans le dépôt de sources ne signifie pas qu'elle est déjà disponible en ligne.

1. Installer les outils nécessaires et télécharger la clé publique dans un répertoire temporaire :

   ```bash
   sudo apt-get update
   sudo apt-get install -y ca-certificates curl gnupg
   met_tmp="$(mktemp -d)"
   curl -fsSL https://packages.myeasytoolkit.com/apt/myeasytoolkit-archive-keyring.gpg -o "$met_tmp/keyring.gpg"
   gpg --show-keys --fingerprint --with-subkey-fingerprint "$met_tmp/keyring.gpg"
   gpg --show-keys --with-colons "$met_tmp/keyring.gpg" | awk -F: '$1 == "pub" { n++ } END { if (n != 1) { print "Nombre de clés principales inattendu" > "/dev/stderr"; exit 1 } }'
   ```

2. Si l'une des commandes échoue, ne pas poursuivre. Comparer **l'empreinte complète de la clé principale et celle de la sous-clé stable** avec les empreintes officielles obtenues par un canal de confiance indépendant. Arrêter en cas de différence ou si les empreintes ne peuvent pas être confirmées. Une empreinte récupérée uniquement sur le même serveur que la clé ne permet pas de vérifier son authenticité en cas de compromission de ce serveur. Les clés de test ne doivent pas être utilisées en production.

3. Après cette vérification, renseigner l'empreinte complète de la **sous-clé stable** vérifiée, puis ajouter la source et les paquets. Remplacer le texte entre apostrophes :

   ```bash
   met_signer='REMPLACER_PAR_EMPREINTE_STABLE_VERIFIEE'
   if [[ "$met_signer" =~ ^[A-F0-9]{40}$ ]] && gpg --show-keys --with-colons "$met_tmp/keyring.gpg" | awk -F: '$1 == "fpr" {print $10}' | grep -Fxq "$met_signer"; then
     sudo install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d &&
     sudo install -m 644 "$met_tmp/keyring.gpg" /usr/share/keyrings/myeasytoolkit-archive-keyring.gpg &&
     met_arch="$(dpkg --print-architecture)" &&
     printf 'deb [arch=%s signed-by=/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg,%s!] https://packages.myeasytoolkit.com/apt stable main\n' "$met_arch" "$met_signer" | sudo tee /etc/apt/sources.list.d/myeasytoolkit.list > /dev/null &&
     sudo apt-get update && sudo apt-get install myeasytoolkit-archive-keyring myeasytoolkit
   else
     echo 'Empreinte de signature invalide ou absente du trousseau : installation interrompue.' >&2
   fi
   ```

Le paquet de clés gère ensuite le fichier référencé par `signed-by`. `apt update` actualise les listes ; `apt upgrade` ou l'installation explicite d'une nouvelle version installe les mises à jour, y compris celles du paquet de clés. Cette procédure ne configure aucun programme de vérification personnalisé à chaque appel d'APT.

La source limite aussi la signature à la sous-clé stable précise. Lors d'une rotation de cette sous-clé, mettre à jour en toute sécurité la liste des empreintes autorisées dans la source APT avant le changement : la mise à jour du seul paquet de clés ne modifie pas automatiquement une empreinte épinglée dans le fichier `.list`.

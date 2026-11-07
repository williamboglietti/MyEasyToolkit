# Installation APT manuelle

Cette procédure concerne Debian et Ubuntu sur les architectures `amd64` et `arm64`. Elle nécessite que la version comprenant le paquet `myeasytoolkit-archive-keyring` ait été publiée ; sa préparation dans le dépôt de sources ne signifie pas qu'elle est déjà disponible en ligne.

1. Installer les outils nécessaires et télécharger la clé publique dans un répertoire temporaire :

   ```bash
   sudo apt-get update
   sudo apt-get install -y ca-certificates curl gnupg
   met_tmp="$(mktemp -d)"
   curl -fsSL https://packages.myeasytoolkit.com/apt/myeasytoolkit-archive-keyring.gpg -o "$met_tmp/keyring.gpg"
   gpg --show-keys --fingerprint "$met_tmp/keyring.gpg"
   gpg --show-keys --with-colons "$met_tmp/keyring.gpg" | awk -F: '$1 == "pub" { n++ } END { if (n != 1) { print "Nombre de clés principales inattendu" > "/dev/stderr"; exit 1 } }'
   ```

2. Si l'une des commandes échoue, ne pas poursuivre. Comparer **l'empreinte complète de la clé principale** affichée avec l'empreinte officielle obtenue par un canal de confiance indépendant. Arrêter si elles diffèrent ou si l'empreinte officielle ne peut pas être confirmée. Une empreinte récupérée uniquement sur le même serveur que la clé ne permet pas de vérifier son authenticité en cas de compromission de ce serveur. Les clés de test ne doivent pas être utilisées en production.

3. Après cette vérification, ajouter la clé et la source APT, puis installer le paquet de clés et l'outil :

   ```bash
   sudo install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d
   sudo install -m 644 "$met_tmp/keyring.gpg" /usr/share/keyrings/myeasytoolkit-archive-keyring.gpg
   met_arch="$(dpkg --print-architecture)"
   printf 'deb [arch=%s signed-by=/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg] https://packages.myeasytoolkit.com/apt stable main\n' "$met_arch" | sudo tee /etc/apt/sources.list.d/myeasytoolkit.list > /dev/null
   sudo apt-get update
   sudo apt-get install myeasytoolkit-archive-keyring myeasytoolkit
   ```

Le paquet de clés gère ensuite le fichier référencé par `signed-by`. `apt update` actualise les listes ; `apt upgrade` ou l'installation explicite d'une nouvelle version installe les mises à jour, y compris celles du paquet de clés. Cette procédure ne configure aucun programme de vérification personnalisé à chaque appel d'APT.

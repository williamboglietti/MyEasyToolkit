# Installation, réparation et désinstallation APT

Ces commandes concernent Debian et Ubuntu sur `amd64` et `arm64`. Elles utilisent Bash, Python 3, curl, les certificats CA du système et gpgv. Le lanceur demande les droits via `sudo` si nécessaire. Les trois commandes deviennent disponibles avec la publication de l’archive signée et du site de distribution.

## Installer ou rétablir le dépôt stable

```bash
curl -fsSL https://myeasytoolkit.com/install.sh | bash
```

Une relance peut rétablir la source dédiée et remplacer un trousseau absent, illisible ou obsolète. Le lanceur utilise des listes APT neuves et vérifie un index signé datant de 90 jours au plus, ainsi que le champ `Valid-Until` lorsque le dépôt le publie. Les fichiers APT précédents sont rétablis si une erreur survient pendant leur remplacement. En cas d’installation de paquet interrompue, utilisez la commande de réparation.

Les empreintes épinglées par la publication stable actuelle sont les suivantes.

- Clé principale `3E484A3CC09A798022AEA0C01A91FD19F9E87AE7`
- Sous-clé de signature `A0EF38D209213D2AB5761B814BBD7ACB126A6842`

Comparez les empreintes à celles publiées par le projet via un canal de confiance indépendant pour auditer une rotation. APT utilise la source `/etc/apt/sources.list.d/myeasytoolkit.list` et le fichier `/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg`, géré par le paquet `myeasytoolkit-archive-keyring`.

## Réparer une installation

```bash
curl -fsSL https://packages.myeasytoolkit.com/repair.sh | bash
```

Le lanceur vérifie le dépôt signé, l’état et l’intégrité des deux paquets, puis teste `myeasytoolkit --version` et `myeasytoolkit --help`. Il termine une configuration de paquet interrompue et restaure les fichiers de l’application à partir de la même version si elle est disponible dans le dépôt signé. Il peut actualiser le paquet de clés à la suite d’une rotation. Les données de l’application sont conservées.

## Désinstaller et purger

```bash
curl -fsSL https://packages.myeasytoolkit.com/uninstall.sh | bash
```

Dans un terminal interactif, vérifiez l’aperçu puis tapez `OUI` et `PURGER`. Le lanceur retire les deux paquets, la source et le trousseau dédiés et les résidus qu’il reconnaît, y compris lorsque les paquets ont déjà été retirés. Il conserve les données utilisateur et les fichiers dont il ne peut pas établir l’appartenance. En cas de montage, de lien ou d’usage partagé, il interrompt la purge pour laisser l’administrateur examiner le chemin indiqué.

Après une interruption, relancez la même commande. Elle présente les actions restantes et demande à nouveau les deux confirmations. Le journal de reprise se trouve dans `/var/lib/myeasytoolkit-apt-removal.json`.

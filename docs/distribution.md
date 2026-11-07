# Préparer une publication

Le workflow « Publish validated release » démarre automatiquement après une CI réussie sur `main`, et peut aussi être lancé manuellement sur `main`. Il refuse de publier si le commit validé n’est plus la tête de `main`, construit les binaires et les deux paquets Debian, génère le dépôt APT, signe l’ensemble de distribution et demande au dépôt MyEasyToolkit.com de le publier.

La publication exige :

- une sous-clé OpenPGP de signature dédiée : son export privé ASCII protégé est placé dans le secret Actions `APT_SIGNING_KEY` et sa phrase secrète dans `APT_SIGNING_PASSPHRASE`. La clé principale privée reste hors de la CI. La nouvelle clé et la transition de confiance APT sont traitées séparément ;
- le secret Actions `SITE_DEPLOY_TOKEN`, limité au dépôt MyEasyToolkit.com avec la permission Actions en écriture ;
- le site doit disposer de ses propres accès Cloudflare et d’une CI verte sur sa branche principale.

Ne jamais committer de clé privée ou de phrase secrète. L'installateur shell publié incorpore l'empreinte de la clé qui a signé les métadonnées APT ; si elle change, les installations existantes doivent faire l'objet d'une procédure de rotation explicite. Les URL de publication sont servies par le Worker du dépôt [MyEasyToolkit.com](https://github.com/williamboglietti/MyEasyToolkit.com).

`bash packaging/build-apt-repository.sh REPERTOIRE_PAQUETS SORTIE EMPREINTE` construit un dépôt APT dans un répertoire encore inexistant. La variable `MET_GPG_PASSPHRASE_FILE` peut désigner un fichier de phrase secrète pour les clés protégées. `bash tests/apt-repository.sh` utilise uniquement une clé éphémère et des fichiers de test sur Linux.

## Télécharger et vérifier un paquet Debian

Le dépôt APT reste la méthode recommandée : sa signature protège ses métadonnées
et les empreintes des paquets. Pour une installation manuelle, chaque publication
prépare aussi ces fichiers :

- `https://packages.myeasytoolkit.com/releases/latest/myeasytoolkit-linux-amd64.deb` et sa signature `.deb.asc` ;
- `https://packages.myeasytoolkit.com/releases/latest/myeasytoolkit-linux-arm64.deb` et sa signature `.deb.asc`.

La signature détachée porte sur le contenu exact du `.deb`. Elle est vérifiée
lors de la préparation de la distribution, avec la clé publique utilisée par le
dépôt. Ces chemins sont disponibles uniquement après la publication effective
d'une version qui inclut cette fonctionnalité.

Sur une machine où la clé du dépôt est déjà installée et approuvée, après avoir
téléchargé le paquet et son fichier `.asc` dans le répertoire courant :

```bash
gpgv --keyring /usr/share/keyrings/myeasytoolkit-archive-keyring.gpg \
  myeasytoolkit-linux-amd64.deb.asc myeasytoolkit-linux-amd64.deb
sudo apt install ./myeasytoolkit-linux-amd64.deb
```

Adapter `amd64` à `arm64` selon l'architecture. Ne lancer l'installation que si
`gpgv` confirme la signature. Sur une machine qui ne possède pas encore la clé,
obtenir la clé publique et confirmer son empreinte par un canal de confiance
avant de l'utiliser. Télécharger la clé et le paquet depuis la même source sans
vérifier l'empreinte ne permet pas, à lui seul, d'authentifier l'éditeur.
Ni `apt install ./paquet.deb` ni `dpkg -i` ne vérifie automatiquement ce fichier
de signature détachée.

Le routage des installateurs et du site est documenté dans le dépôt MyEasyToolkit.com.

La clé publique et son empreinte sont versionnées dans `packaging/`. La publication refuse une clé privée qui ne correspond pas à cette empreinte. Prévoir la rotation avant l'expiration des clés et la distribution de la nouvelle confiance aux installations existantes.

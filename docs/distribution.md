# Préparer une publication

Le workflow « Publish validated release » est lancé manuellement sur `main`. Il exige une exécution réussie du workflow CI sur le commit courant, construit les binaires et les deux paquets Debian, génère les métadonnées APT signées et publie le Worker Cloudflare. La page `web/download.html` doit être présente avant la publication.

La publication exige :

- une sous-clé OpenPGP de signature dédiée : son export privé ASCII protégé est placé dans le secret Actions `APT_SIGNING_KEY` et sa phrase secrète dans `APT_SIGNING_PASSPHRASE`. La clé principale privée reste hors de la CI. La nouvelle clé et la transition de confiance APT sont traitées séparément ;
- le secret Actions `CLOUDFLARE_API_TOKEN`, limité aux permissions nécessaires au Worker, aux routes et aux domaines ;
- la variable Actions `CLOUDFLARE_ACCOUNT_ID` ;
- la zone `myeasytoolkit.com` sur le compte Cloudflare et les domaines prévus disponibles.

Ne jamais committer de clé privée ou de phrase secrète. L'installateur shell publié incorpore l'empreinte de la clé qui a signé les métadonnées APT ; si elle change, les installations existantes doivent faire l'objet d'une procédure de rotation explicite. Les URL de publication sont servies par des assets Workers. Le domaine principal ne reçoit que les deux routes d'installation indiquées dans `web/wrangler.jsonc`.

`bash packaging/build-apt-repository.sh REPERTOIRE_PAQUETS SORTIE EMPREINTE [PAQUET_CLES.deb]` construit un dépôt APT dans un répertoire encore inexistant. La variable `MET_GPG_PASSPHRASE_FILE` peut désigner un fichier de phrase secrète pour les clés protégées. `bash tests/apt-repository.sh` utilise uniquement des clés éphémères et des fichiers de test sur Linux.

## Préparer le paquet de clés publiques

Sous Linux, `bash packaging/build-archive-keyring-deb.sh CLE_PUBLIQUE.gpg EMPREINTES VERSION` prépare `dist/keyring/myeasytoolkit-archive-keyring_VERSION_all.deb`. Le fichier est un trousseau OpenPGP binaire. Indiquer toutes les empreintes principales complètes en majuscules, séparées par des virgules. La construction refuse les clés privées et les clés publiques absentes de cette liste, ou les empreintes qui ne correspondent à aucune clé.

Ce paquet contient uniquement le trousseau public et ne configure aucun hook APT. Il peut contenir momentanément l'ancienne et la nouvelle clé pendant une rotation prévue. Les sources APT qui référencent ce fichier acceptent les clés qu'il contient : partager le fichier entre plusieurs dépôts partage donc leur confiance. Ne pas utiliser une clé de test comme clé de production.

`bash packaging/stage-release.sh ARTIFACTS SORTIE EMPREINTE` prépare aussi ce paquet et l'ajoute au dépôt. Pour préparer une rotation, l'appel accepte en outre `TROUSSEAU_PUBLIC EMPREINTES VERSION_DU_PAQUET_DE_CLES` : le trousseau peut contenir les deux clés et la liste doit inclure la clé qui signe actuellement le dépôt. Augmenter la version du paquet de clés pour que les clients puissent le mettre à jour. L'export public utilisé au premier amorçage reste celui de la clé de signature courante.

La publication automatisée utilise actuellement l'appel à trois paramètres et prépare un trousseau à une seule clé. Pour publier une transition à deux clés, il faudra adapter et tester la chaîne de publication avec les paramètres supplémentaires avant de changer la clé de signature ; cette préparation ne rend pas la rotation automatique.

Les étapes d'[installation manuelle](installation-apt.md) et de [réponse à une compromission](incident-cle-apt.md) s'appliquent après validation et publication effectives de cette version. Aucune clé de production ni migration n'est réalisée par leur préparation.

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

La route `/` de `get.myeasytoolkit.com` reconnaît PowerShell et les navigateurs ; les autres clients reçoivent l'installateur shell, qui détecte lui-même la plateforme. Les en-têtes HTTP ne permettent pas de déduire fiablement le système d'exploitation de tous les clients.

La clé publique et son empreinte sont versionnées dans `packaging/`. La publication refuse une clé privée qui ne correspond pas à cette empreinte. Prévoir la rotation avant l'expiration des clés et la distribution de la nouvelle confiance aux installations existantes.

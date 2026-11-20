# Préparer une publication

Le workflow « Publish validated release » peut être lancé manuellement sur `main`. Le lancement automatique après une CI réussie sur `main` est désactivé tant que la variable de dépôt `PACKAGES_MYEASYTOOLKIT_COM_DEPLOY_ENABLED` n'est pas définie à `true`. Il refuse de publier si le commit validé n’est plus la tête de `main`, construit les binaires et les deux paquets Debian, génère le dépôt APT, signe l’ensemble de distribution et demande au dépôt MyEasyToolkit.com de le publier.

La publication exige :

- une sous-clé OpenPGP de signature dédiée : son export privé ASCII protégé est placé dans le secret `APT_SIGNING_KEY` de l'environnement `prod` et sa phrase secrète dans `APT_SIGNING_PASSPHRASE`, au même endroit. La clé principale privée reste hors de la CI. La nouvelle clé et la transition de confiance APT sont traitées séparément ;
- le secret `PACKAGES_MYEASYTOOLKIT_COM` de l'environnement `prod` : un jeton GitHub (le jeton Cloudflare du même nom est dans MyEasyToolkit.com), nommé d'après l'hôte `packages.myeasytoolkit.com` que la publication met à jour, limité au dépôt MyEasyToolkit.com avec la permission Actions en écriture ;
- le site doit disposer de ses propres accès Cloudflare, d’une CI verte sur sa branche principale et d'un runner de déploiement disponible ;
- les deux dépôts doivent contenir le même trousseau public de production. Activer ensuite `PACKAGES_MYEASYTOOLKIT_COM_DEPLOY_ENABLED` seulement après validation du parcours complet.

L'environnement GitHub `prod` n'accepte que la branche `main` : les jobs `validate` et `publish` de la publication et le job du workflow « Verify distribution signing key » le déclarent pour lire ces trois secrets. Un secret ne se relit pas, il se remplace :

```bash
gh secret set APT_SIGNING_KEY --env prod --repo williamboglietti/MyEasyToolkit
gh secret set APT_SIGNING_PASSPHRASE --env prod --repo williamboglietti/MyEasyToolkit
gh secret set PACKAGES_MYEASYTOOLKIT_COM --env prod --repo williamboglietti/MyEasyToolkit
```

Ne jamais committer de clé privée ou de phrase secrète. L'installateur shell publié incorpore l'empreinte de la clé qui a signé les métadonnées APT ; si elle change, les installations existantes doivent faire l'objet d'une procédure de rotation explicite. Les URL de publication sont servies par le Worker du dépôt [MyEasyToolkit.com](https://github.com/williamboglietti/MyEasyToolkit.com).

Le workflow manuel « Verify distribution signing key » vérifie sur `main` les deux secrets de signature, l'absence de clé principale privée, leur correspondance avec le trousseau public et l'accès du jeton au workflow du site, sans créer de version ni déployer de site. La lecture du workflow ne prouve pas que le jeton pourra le déclencher ; ce droit doit aussi être vérifié lors de la réception du parcours de publication.

`bash packaging/build-apt-repository.sh REPERTOIRE_PAQUETS SORTIE EMPREINTE [PAQUET_CLES.deb]` construit un dépôt APT dans un répertoire encore inexistant. La variable `MET_GPG_PASSPHRASE_FILE` peut désigner un fichier de phrase secrète pour les clés protégées. `bash tests/apt-repository.sh` utilise uniquement des clés éphémères et des fichiers de test sur Linux.

## Préparer le paquet de clés publiques

Sous Linux, `bash packaging/build-archive-keyring-deb.sh CLE_PUBLIQUE.gpg EMPREINTES VERSION` prépare `dist/keyring/myeasytoolkit-archive-keyring_VERSION_all.deb`. Le fichier est un trousseau OpenPGP binaire. Indiquer toutes les empreintes principales complètes en majuscules, séparées par des virgules. La construction refuse les clés privées et les clés publiques absentes de cette liste, ou les empreintes qui ne correspondent à aucune clé.

Ce paquet contient uniquement le trousseau public et ne configure aucun hook APT. Il peut contenir momentanément l'ancienne et la nouvelle clé pendant une rotation prévue. Les sources APT qui référencent ce fichier acceptent les clés qu'il contient : partager le fichier entre plusieurs dépôts partage donc leur confiance. Ne pas utiliser une clé de test comme clé de production.

`bash packaging/stage-release.sh ARTIFACTS SORTIE EMPREINTE` prépare aussi ce paquet et l'ajoute au dépôt. Pour préparer une rotation, l'appel accepte en outre `TROUSSEAU_PUBLIC EMPREINTES VERSION_DU_PAQUET_DE_CLES` : le trousseau peut contenir les deux clés et la liste doit inclure la clé qui signe actuellement le dépôt. Augmenter la version du paquet de clés pour que les clients puissent le mettre à jour. L'export public utilisé au premier amorçage reste celui de la clé de signature courante.

La publication automatisée utilise actuellement l'appel à trois paramètres et prépare un trousseau à une seule clé. Pour publier une transition à deux clés, il faudra adapter et tester la chaîne de publication avec les paramètres supplémentaires avant de changer la clé de signature ; cette préparation ne rend pas la rotation automatique.

L'installateur généré vérifie que le trousseau initial contient uniquement le signataire stable prévu. La source APT référence ce fichier sans épingler d'empreinte dans la source : cela permet au paquet de clés de préparer une rotation. Le trousseau fourni par le paquet est construit à partir des seules sous-clés de production explicitement autorisées. Les installations préexistantes nécessitent une migration distincte et vérifiée.

La préparation du [canal de test](apt-canaux.md) est distincte de sa publication, qui n'est pas activée par ce changement.

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

Le routage des installateurs et du site est documenté dans le dépôt MyEasyToolkit.com.

La clé publique et son empreinte sont versionnées dans `packaging/`. La publication refuse une clé privée qui ne correspond pas à cette empreinte. Prévoir la rotation avant l'expiration des clés et la distribution de la nouvelle confiance aux installations existantes.

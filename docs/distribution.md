# Préparer une publication

Le workflow « Publish validated release » est lancé manuellement sur `main`. Il exige une exécution réussie du workflow CI sur le commit courant, construit les binaires et les deux paquets Debian, génère les métadonnées APT signées et publie le Worker Cloudflare. La page `web/download.html` doit être présente avant la publication.

La publication exige :

- une sous-clé OpenPGP de signature dédiée : son export privé ASCII protégé est placé dans le secret Actions `APT_SIGNING_KEY` et sa phrase secrète dans `APT_SIGNING_PASSPHRASE`. La clé principale privée reste hors de la CI. La nouvelle clé et la transition de confiance APT sont traitées séparément ;
- le secret Actions `CLOUDFLARE_API_TOKEN`, limité aux permissions nécessaires au Worker, aux routes et aux domaines ;
- la variable Actions `CLOUDFLARE_ACCOUNT_ID` ;
- la zone `myeasytoolkit.com` sur le compte Cloudflare et les domaines prévus disponibles.

Ne jamais committer de clé privée ou de phrase secrète. L'installateur shell publié incorpore l'empreinte de la clé qui a signé les métadonnées APT ; si elle change, les installations existantes doivent faire l'objet d'une procédure de rotation explicite. Les URL de publication sont servies par des assets Workers. Le domaine principal ne reçoit que les deux routes d'installation indiquées dans `web/wrangler.jsonc`.

`bash packaging/build-apt-repository.sh REPERTOIRE_PAQUETS SORTIE EMPREINTE` construit un dépôt APT dans un répertoire encore inexistant. La variable `MET_GPG_PASSPHRASE_FILE` peut désigner un fichier de phrase secrète pour les clés protégées. `bash tests/apt-repository.sh` utilise uniquement une clé éphémère et des fichiers de test sur Linux.

## Préparer le paquet de clés publiques

Le paquet de clés et son actualisation sont en cours de préparation. Sous Linux, la commande suivante construit un paquet **de test** :

```bash
bash packaging/build-archive-keyring-deb.sh \
  CLE_PROJET_PUBLIQUE.gpg EMPREINTE_PROJET VERSION \
  CLE_AUTORITE_PUBLIQUE.gpg EMPREINTE_AUTORITE 'IDENTITE PUBLIQUE DU PROJET'
```

Les deux fichiers sont des certificats OpenPGP publics binaires ; la construction refuse toute clé privée. La clé de projet doit être une clé principale indépendante capable de signer, dont l'identité indiquée est certifiée par l'autorité, pour une durée limitée. Elle est destinée à signer le dépôt et les paquets. L'autorité est réservée à la certification et ne figure dans le paquet que sous sa forme publique.

Le prototype utilise un catalogue public `https://packages.myeasytoolkit.com/apt/certificates.gpg`. Lors d'un `apt update`, un programme fourni par le paquet vérifie la certification par l'autorité, conserve les révocations déjà observées et met à jour la clé de projet acceptée par APT. Il ne s'agit pas d'une fonctionnalité native de délégation d'APT. Les certifications doivent être renouvelées avant leur expiration. Si une machine n'a jamais reçu une révocation, un ancien catalogue peut encore être présenté jusqu'à l'expiration de la certification : celle-ci limite cette période sans la supprimer.

Si la vérification est impossible, le prototype suspend les installations et mises à jour de MyEasyToolkit ; les programmes installés peuvent toujours être lancés. Il préserve les installations des autres dépôts lorsqu'elles sont demandées séparément. Une opération APT qui inclut aussi MyEasyToolkit est interrompue et doit être relancée pour les autres paquets seuls. Il vérifie aussi que les listes APT mises en cache ont été signées par une clé de projet encore autorisée. Ce contrôle vise la source HTTPS `/apt`, distribution `stable`. Les installations directes avec `dpkg` et les téléchargements seuls ne passent pas par ce contrôle. Une configuration APT personnalisée ou une défaillance du système de fichiers peut réduire la protection : ne pas assimiler ce prototype à une garantie universelle.

**Ce mécanisme n'est pas encore publié ni relié à l'installateur ou au workflow de livraison.** Sa mise en service nécessite notamment la publication du paquet et du catalogue, le choix des clés de production et une procédure de migration testée. Ne pas utiliser de clés de test en production.

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

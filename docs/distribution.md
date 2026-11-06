# Préparer une publication

Le workflow « Publish validated release » est lancé manuellement sur `main`. Il exige une exécution réussie du workflow CI sur le commit courant, construit les binaires et les deux paquets Debian, génère le dépôt APT, signe l’ensemble de distribution et demande au dépôt MyEasyToolkit.com de le publier.

La publication exige :

- une clé OpenPGP dédiée, dont la clé privée ASCII protégée est placée dans le secret Actions `APT_SIGNING_KEY` et la phrase secrète dans `APT_SIGNING_PASSPHRASE` ; la sauvegarde chiffrée est sous `~/Library/Application Support/MyEasyToolkit/apt-signing/` et sa phrase secrète est dans le trousseau macOS sous « MyEasyToolkit APT signing passphrase » ;
- le secret Actions `SITE_DEPLOY_TOKEN`, limité au dépôt MyEasyToolkit.com avec la permission Actions en écriture ;
- le site doit disposer de ses propres accès Cloudflare et d’une CI verte sur sa branche principale.

Ne jamais committer de clé privée ou de phrase secrète. L'installateur shell publié incorpore l'empreinte de la clé qui a signé les métadonnées APT ; si elle change, les installations existantes doivent faire l'objet d'une procédure de rotation explicite. Les URL de publication sont servies par le Worker du dépôt [MyEasyToolkit.com](https://github.com/williamboglietti/MyEasyToolkit.com).

`bash packaging/build-apt-repository.sh REPERTOIRE_PAQUETS SORTIE EMPREINTE` construit un dépôt APT dans un répertoire encore inexistant. La variable `MET_GPG_PASSPHRASE_FILE` peut désigner un fichier de phrase secrète pour les clés protégées. `bash tests/apt-repository.sh` utilise uniquement une clé éphémère et des fichiers de test sur Linux.

La route `/` de `get.myeasytoolkit.com` reconnaît PowerShell et les navigateurs ; les autres clients reçoivent l'installateur shell, qui détecte lui-même la plateforme. Les en-têtes HTTP ne permettent pas de déduire fiablement le système d'exploitation de tous les clients.

La clé publique et son empreinte sont versionnées dans `packaging/`. La publication refuse une clé privée qui ne correspond pas à cette empreinte. La clé actuelle expire trois ans après sa création ; prévoir une rotation avant son expiration.

# Chaîne de confiance APT : état et proposition

Document de travail. Les choix de l'identité, des clés et de leur stockage restent à valider ; aucun changement de confiance ou de publication n'est effectué par ce document.

## État observé le 7 novembre 2026

- Le dépôt public utilise une clé OpenPGP principale Ed25519 de signature et de certification, sans sous-clé. Son identité est `MyEasyToolkit APT archive signing` et son empreinte est `3DDACB1CAEC51E8466DB12456A0AFA48DB9C62D5`.
- L'installateur télécharge la clé publique et écrit un fichier de trousseau local référencé par `signed-by`. Il n'existe pas de paquet APT qui mette à jour ce trousseau.
- Le dépôt contient des paquets `0.1.0` construits depuis une révision antérieure aux améliorations actuelles. Le code courant porte aussi `0.1.0` : il faut une version Debian supérieure avant de publier une mise à jour.
- La publication existante est manuelle. La séparation et la publication automatique sont en cours dans la PR #3 ; il faut vérifier leurs prérequis et leur intégration avant toute mise en service.
- Une sauvegarde chiffrée de la clé est présente localement et une entrée de phrase secrète existe dans le trousseau de connexion du Mac. Leur restauration ensemble n'a pas encore été vérifiée et leur présence sur un support indépendant n'est pas établie.

## Identité publique

L'UID OpenPGP peut porter un nom, un commentaire et une adresse de contact ; ces éléments sont publics et ne prouvent pas l'identité de leur auteur. L'empreinte, vérifiée par un canal de confiance, identifie la clé. La clé publique TWT Cloud consultée porte `TWT Cloud Release Signing (production) <security@twtcloud.org>`. William a validé le libellé `MyEasyToolkit Release Signing (production) <security@myeasytoolkit.com>` et prévoit de s'occuper de la réception de cette adresse ultérieurement ; aucun enregistrement MX n'a été trouvé le 7 novembre 2026. Il faudra vérifier la réception avant d'utiliser cette adresse comme canal d'alerte.

## Architecture proposée

1. Une clé principale dédiée à la certification, conservée chiffrée hors de la CI, avec sauvegarde indépendante et restauration testée. La méthode d'accès, la durée de validité et le choix de conserver ou remplacer la clé actuelle sont à décider.
2. Une sous-clé de signature pour les publications, seule partie privée mise à disposition de la CI. Contrôler l'export : la clé privée principale ne doit pas être utilisable sur le runner. Protéger aussi la sous-clé et limiter l'accès aux secrets et à la publication.
3. Un certificat de révocation de la clé principale conservé séparément et protégé. Préparer aussi la procédure de révocation d'une sous-clé : celle-ci doit être diffusée et prise en compte dans le trousseau public mis à jour ; sa simple publication sur un site ou serveur de clés ne met pas à jour les clients APT. Ne pas supposer qu'ajouter le certificat au trousseau suffit : GnuPG indique que `gpgv` ne contrôle pas les clés expirées ou révoquées. Tester le comportement d'APT et retirer les clés compromises du trousseau de confiance si nécessaire.
4. Un paquet Debian `myeasytoolkit-archive-keyring` gérant le fichier référencé par `signed-by`. Distribuer ses nouvelles versions via le dépôt authentifié ; APT ne l'installe que lors d'une installation ou mise à niveau, pas pendant `apt update` seul.
5. Une documentation publique des empreintes, de leur période de validité et d'un canal de secours permettant de les vérifier indépendamment du serveur de distribution. Une empreinte livrée par le même canal que la clé ne constitue pas à elle seule une preuve indépendante.

## Migration sans casser les clients existants

Tant que l'ancienne clé est considérée fiable, publier d'abord, sous l'ancienne signature, un paquet de trousseau qui accepte les anciennes et nouvelles clés publiques. Assurer explicitement son installation sur les machines ayant déjà `0.1.0`, puis maintenir une période de chevauchement suffisante avant tout changement du signataire. Une nouvelle dépendance ne garantit pas à elle seule qu'`apt-get upgrade` installera le nouveau paquet : tester le comportement et documenter une commande d'installation ciblée si nécessaire. Faire évoluer les versions APT de façon monotone et éviter de réutiliser le même numéro pour des contenus différents.

Une machine qui n'a pas installé le trousseau de transition avant le changement peut refuser les nouvelles signatures : prévoir une procédure de récupération avec vérification de l'empreinte par un canal indépendant. Vérifier également la reprise du fichier de trousseau déjà installé par le script, sa propriété par `dpkg` et le comportement d'une réinstallation de l'installateur.

Le bootstrap actuel refuse plus d'une clé principale et compare le trousseau publié à un seul trousseau épinglé ; le workflow de livraison impose également cette correspondance. Une transition avec deux principales exige donc d'adapter et de tester ces contrôles avant de publier le trousseau mixte. Ne pas simplement remplacer les clés : les clients déjà installés refuseraient les signatures de la nouvelle principale.

## Actualisation avant `apt update` : option à étudier

Le dépôt `thewebtouch.ovh` contient un prototype TWT Cloud : un hook `APT::Update::Pre-Invoke` récupère un bundle de clés avant la vérification APT, épingle l'empreinte principale et conserve l'historique des sous-clés révoquées. Son état documenté est du staging ; le bundle et la chaîne complète de production ne sont pas démontrés. Ce mécanisme est une option pour MyEasyToolkit, à comparer avec la seule mise à jour par paquet et à tester indépendamment.

Si l'option est retenue, tester notamment : authenticité des certifications et révocations, retrait des sous-clés interdites, réutilisation d'un ancien bundle, indisponibilité réseau, interruption pendant l'écriture, processus simultanés et compromission de la sous-clé ou de la principale. Le hook TWT conserve le trousseau précédent en cas d'erreur réseau ; cela assure la disponibilité mais peut retarder la connaissance d'une révocation. Définir la politique de fraîcheur et le comportement en cas d'échec. Un attaquant capable de bloquer les mises à jour peut retarder l'information de révocation : aucune consultation réseau ne garantit une réaction immédiate.

## Compromission et révocation

Ne pas considérer une mise à jour signée par une clé compromise comme preuve suffisante pour rétablir la confiance. Diffuser l'alerte, les nouvelles empreintes et les instructions par un canal indépendant ; suspendre les publications avec la clé compromise et appliquer la procédure de récupération à chaque client concerné. Une sous-clé compromise peut être révoquée par la clé principale, mais les clients ne seront protégés qu'après réception et application de la révocation ou retrait de la sous-clé par un chemin jugé fiable. Si la clé principale est compromise, il faut une nouvelle racine de confiance et une nouvelle validation côté client. Une machine déjà compromise peut nécessiter un examen ou une reconstruction supplémentaires.

## Vérifications à réaliser avant livraison

- Essai local sur macOS avec une paire Ed25519 jetable : clé principale de certification, sous-clé de signature et certificat de révocation créés ; export limité aux sous-clés importé dans un trousseau isolé, signature vérifiée et tentative de modifier la clé principale refusée. Cet essai ne valide pas encore la restauration de la clé de production, APT ou les workflows CI.
- Tester sur Debian et Ubuntu : installation existante 0.1.0, installation neuve, migration du fichier de clé, mise à niveau de l'application et du paquet de clés.
- Tester avec des clés de test éphémères : rotation normale avec chevauchement, machine n'ayant pas encore reçu le trousseau de transition, sous-clé révoquée et signature non autorisée.
- Vérifier que la CI ne détient que la sous-clé attendue et que les empreintes utilisées à la construction et au déploiement correspondent.
- Tester la restauration d'une sauvegarde sur un environnement isolé sans divulguer la clé ni sa phrase secrète.
- Vérifier la disponibilité et l'intégrité des fichiers publics, les mises en cache et la réponse APT sur HTTP(S) ; décider des protections contre les métadonnées périmées ou rejouées.
- Documenter la publication d'une version plus récente et la différence entre `apt update` et `apt upgrade`.

Références : [apt-secure](https://manpages.debian.org/bookworm/apt/apt-secure.8.en.html), [sources.list et signed-by](https://manpages.debian.org/bookworm/apt/sources.list.5.en.html), [apt-get](https://manpages.debian.org/bookworm/apt/apt-get.8.en.html), [gpgv](https://www.gnupg.org/documentation/manuals/gnupg/gpgv.html), [gestion des clés GnuPG](https://gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html).

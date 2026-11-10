# Prototype de vérification de mises à jour

Cette expérience autonome ne télécharge, n'installe et ne lance aucune mise à jour. Elle ne modifie pas les installateurs ni les fichiers publiés. Elle n'est pas utilisée par MyEasyToolkit et n'est pas prête pour la production.

Le vérificateur contrôle la signature OpenPGP détachée d'un manifeste JSON brut, avec la clé publique du projet et l'empreinte exacte de sa sous-clé de production. Il vérifie l'état de validité et de révocation contenu dans le certificat qu'il possède, la date limite du manifeste, la plateforme, un nom de fichier précis, sa taille et son empreinte SHA-256. Il ne prend pas la clé publique du serveur. L'exécutable expérimental accepte des fichiers locaux et n'installe rien.

Les tests utilisent exclusivement des clés jetables dont seules les parties publiques et les signatures sont conservées. Ils testent des manifestes pour macOS et Windows, ainsi que les erreurs de signature, de signataire, de plateforme, de contenu, de taille, de nom, d'expiration du manifeste et d'expiration de certificat.

Une seconde expérience simule une politique de retour arrière à partir d'un catalogue signé référençant plusieurs versions. Le catalogue est distinct du manifeste initial : son numéro augmente même lorsque l'éditeur recommande une version antérieure. Un catalogue plus ancien, ou différent sous un numéro déjà accepté, est refusé. Un retour choisi par l'utilisateur et un retour recommandé par l'éditeur nécessitent tous deux une confirmation. Après simulation d'installation réussie, la version est maintenue jusqu'à une reprise explicite des mises à jour ; un nouveau correctif est signalé sans être installé automatiquement. Une installation échouée ne change pas l'état simulé.

Les tests simulent également un redémarrage par sérialisation de l'état, mais cette persistance n'est pas intégrée à l'application : aucune opération d'installation ni aucun état utilisateur durable n'est créé par cette expérience.

```bash
cargo test --locked --manifest-path experiments/verification-mises-a-jour/Cargo.toml
```

Pour vérifier une signature détachée déjà publiée, sans installer le fichier :

```bash
cargo run --locked --manifest-path experiments/verification-mises-a-jour/Cargo.toml \
  --example signature-production -- FICHIER SIGNATURE
```

## Limites à résoudre avant intégration

- Ce format de manifeste est expérimental ; aucun manifeste macOS ou Windows de ce type n'est encore publié ou signé par la CI. Il faut étudier TUF et le comparer avant de choisir un format de production.
- La politique de retour arrière est une simulation ; elle n'est pas intégrée à un téléchargeur ou un installateur. Avant toute utilisation réelle, il faut persister l'état vérifié de façon atomique et fiable, tester les interruptions, la corruption, l'horloge système, la première installation et le gel des métadonnées, et vérifier que l'interface transmet effectivement la confirmation de l'utilisateur.
- Le catalogue utilise actuellement une seule sous-clé de CI : si cette clé est compromise, elle peut signer des informations malveillantes, y compris un numéro trop élevé. Il faut concevoir la séparation des rôles, la récupération et la rotation avec une autorité distincte.
- Le certificat incorporé est une copie fixe : une révocation ou une nouvelle sous-clé publiée ultérieurement ne peut pas être découverte automatiquement. Il faut concevoir et tester la rotation et la récupération avec une autorité distincte de la clé compromise.
- Le modèle de téléchargement HTTPS, ses limites de taille, le téléchargement atomique et la protection contre la substitution entre vérification et installation restent à implémenter. Aucun téléchargement ou remplacement n'est prévu ici.
- Le backend cryptographique Rust de Sequoia est activé en mode expérimental et accepte des opérations à temps variable. La vérification ici porte sur des données et clés publiques, mais le choix du backend, sa maintenance et sa compatibilité demandent une revue avant production.
- Sequoia OpenPGP est distribué sous licence LGPL-2.0-or-later : examiner les obligations de distribution applicables avant toute intégration dans l'exécutable distribué.
- La CI exécute également les tests de cette expérience sur les runners macOS et Windows. Vérifier leurs résultats avant toute décision d'intégration.
- La première installation reste un problème distinct : un script obtenu du réseau ne peut pas établir lui-même sa propre authenticité sans point de confiance obtenu préalablement.

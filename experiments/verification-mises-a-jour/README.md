# Prototype de vérification de mises à jour

Cette expérience autonome ne télécharge, n'installe et ne lance aucune mise à jour. Elle ne modifie pas les installateurs ni les fichiers publiés. Elle n'est pas utilisée par MyEasyToolkit et n'est pas prête pour la production.

Le vérificateur contrôle la signature OpenPGP détachée d'un manifeste JSON brut, avec la clé publique du projet et l'empreinte exacte de sa sous-clé de production. Il vérifie l'état de validité et de révocation contenu dans le certificat qu'il possède, la date limite du manifeste, la plateforme, un nom de fichier précis, sa taille et son empreinte SHA-256. Il ne prend pas la clé publique du serveur. L'exécutable expérimental accepte des fichiers locaux et n'installe rien.

Les tests utilisent exclusivement des clés jetables dont seules les parties publiques et les signatures sont conservées. Ils testent des manifestes pour macOS et Windows, ainsi que les erreurs de signature, de signataire, de plateforme, de contenu, de taille, de nom, d'expiration du manifeste et d'expiration de certificat.

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
- L'expiration seule ne prévient pas le retour à une ancienne version encore valide : il faut mémoriser l'état vérifié et protéger contre le retour arrière et le gel des métadonnées.
- Le certificat incorporé est une copie fixe : une révocation ou une nouvelle sous-clé publiée ultérieurement ne peut pas être découverte automatiquement. Il faut concevoir et tester la rotation et la récupération avec une autorité distincte de la clé compromise.
- Le modèle de téléchargement HTTPS, ses limites de taille, le téléchargement atomique et la protection contre la substitution entre vérification et installation restent à implémenter. Aucun téléchargement ou remplacement n'est prévu ici.
- Le backend cryptographique Rust de Sequoia est activé en mode expérimental et accepte des opérations à temps variable. La vérification ici porte sur des données et clés publiques, mais le choix du backend, sa maintenance et sa compatibilité demandent une revue avant production.
- Sequoia OpenPGP est distribué sous licence LGPL-2.0-or-later : examiner les obligations de distribution applicables avant toute intégration dans l'exécutable distribué.
- Un contrôle `cargo check` ciblant Windows ne remplace pas l'exécution des tests sur une machine Windows. La CI principale ne teste pas automatiquement cette expérience autonome.
- La première installation reste un problème distinct : un script obtenu du réseau ne peut pas établir lui-même sa propre authenticité sans point de confiance obtenu préalablement.

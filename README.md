# MyEasyToolkit

Navigateur de scripts dans le terminal, utilisable au clavier et à la souris lorsque le terminal le permet. Au démarrage, le dossier courant est affiché. Choisissez une source en haut de l’écran :

- **Local** : parcourez les fichiers de votre machine, à partir du dossier dans lequel vous avez lancé l’outil.
- **HTTP** : saisissez l’adresse de votre index HTTP(S) de type Apache. L’adresse préremplie peut être modifiée pour utiliser `http://` si nécessaire.
- **GitHub** : saisissez l’adresse d’un dépôt public, par exemple `https://github.com/community-scripts/ProxmoxVE`. La navigation utilise la branche par défaut. Les dépôts privés et les liens vers une branche ou un sous-dossier ne sont pas encore pris en charge ; GitHub limite également les requêtes non authentifiées et les listes de dossiers à 1 000 éléments.

```bash
myeasytoolkit
myeasytoolkit https://github.com/community-scripts/ProxmoxVE
```

Cliquez sur une source ou utilisez les touches `1`, `2` et `3`. Cliquez sur un élément ou naviguez avec les flèches et Entrée ; Retour arrière remonte, `r` actualise et `q` quitte. Dans les champs de saisie, les flèches déplacent le curseur, Début/Fin rejoignent les extrémités et le collage du terminal est pris en charge. Une erreur de connexion laisse l’adresse modifiable.

Les scripts `.sh` et `.ps1` ne sont exécutés qu’après confirmation, avec les droits de l’utilisateur courant. Les scripts locaux sont exécutés depuis leur emplacement d’origine ; les scripts distants sont téléchargés individuellement. Un script distant qui dépend d’autres fichiers du dépôt doit les récupérer lui-même. Les scripts `.sh` nécessitent Bash et les scripts `.ps1` nécessitent PowerShell.

Pour les dépôts HTTP protégés, les identifiants Basic sont demandés lors d’une réponse 401, restent en mémoire pendant la session et ne sont envoyés qu’en HTTPS (sauf sur localhost pour les tests).

## Développement

```bash
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo run
```

Sous Linux, `bash packaging/build-deb.sh` construit un paquet dans `dist/`. La CI produit des paquets Debian statiques pour amd64 et arm64. La préparation des installateurs, du dépôt APT signé et du transfert vers le site est décrite dans [docs/distribution.md](docs/distribution.md). La publication nécessite la configuration des accès et de la clé de signature.

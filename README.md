# MyEasyToolkit

Navigateur de dépôts de scripts dans le terminal. Indiquez une URL d'index HTTP(S) de type Apache, par exemple `https://mystorage.ovh/` ; parcourez les dossiers au clavier ou à la souris et confirmez avant d'exécuter un script `.sh` ou `.ps1`.

```text
myeasytoolkit https://mystorage.ovh/
```

Les flèches et Entrée naviguent, Retour arrière remonte, `o` ouvre un autre dépôt, `r` actualise et `q` quitte. Les identifiants HTTP Basic sont demandés lors d'une réponse 401, restent en mémoire pendant la session et ne sont pas envoyés en HTTP (sauf sur localhost pour les tests). Les scripts `.sh` nécessitent Bash ; les scripts `.ps1` nécessitent PowerShell. L'outil exécute les scripts avec les droits de l'utilisateur courant.

## Développement

```bash
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo run -- https://mystorage.ovh/
```

Sous Linux, `bash packaging/build-deb.sh` construit un paquet dans `dist/`. La CI produit des paquets Debian statiques pour amd64 et arm64. La publication, les installateurs et les dépôts signés restent à mettre en place.

# MyEasyToolkit

Navigateur de scripts dans le terminal, utilisable au clavier et à la souris lorsque le terminal le permet. Au démarrage, le dossier courant est affiché. Choisissez une source en haut de l’écran :

- **Local** : parcourez les fichiers de votre machine, à partir du dossier dans lequel vous avez lancé l’outil.
- **HTTP** : saisissez l’adresse de votre index HTTP(S) de type Apache. L’adresse préremplie peut être modifiée pour utiliser `http://` si nécessaire.
- **GitHub** : saisissez l’adresse d’un dépôt public, par exemple `https://github.com/community-scripts/ProxmoxVE`. La navigation utilise la branche par défaut. Les dépôts privés et les liens vers une branche ou un sous-dossier ne sont pas encore pris en charge ; GitHub limite également les requêtes non authentifiées et les listes de dossiers à 1 000 éléments.

```bash
myeasytoolkit
myeasytoolkit https://github.com/community-scripts/ProxmoxVE
```

Au démarrage, la sélection est placée sur les sources : utilisez les flèches gauche et droite puis Entrée pour choisir, ou la flèche bas pour rejoindre les fichiers. Depuis le premier fichier, la flèche haut revient aux sources ; Tab permet également de passer d’une zone à l’autre. Vous pouvez aussi cliquer sur une source ou utiliser les touches `1`, `2` et `3`. Cliquez sur un élément ou naviguez avec les flèches et Entrée ; Retour arrière remonte, `r` actualise et `q` quitte. Dans les champs de saisie, les flèches déplacent le curseur, Début/Fin rejoignent les extrémités et le collage du terminal est pris en charge. Une erreur de connexion laisse l’adresse modifiable.

Par défaut, seuls les dossiers et les scripts dont l’interpréteur est détecté sont affichés : Bash pour `.sh`, PowerShell pour `.ps1`. Le filtre vérifie la présence de l’interpréteur, pas la compatibilité réelle des commandes du script avec votre système. Cliquez sur « Tous » ou appuyez sur `t` pour afficher les autres fichiers ; `.htaccess` et `.htpasswd` restent masqués. Seuls les scripts `.sh` et `.ps1` peuvent être lancés.

Un fichier texte UTF-8 peut décrire un script : placez `sauvegarde.txt` à côté de `sauvegarde.sh` (ou `sauvegarde.ps1`). La première ligne non vide sert de résumé dans la liste lorsque la place le permet ; le panneau Description affiche le texte complet. Sélectionnez une ligne au clavier ou cliquez dessus, puis faites défiler le panneau avec la molette, les boutons fléchés ou `Page précédente` / `Page suivante`. Le fichier texte doit apparaître dans le même dossier de l’index HTTP ou du dépôt GitHub. Sa lecture se fait en arrière-plan et sa taille est limitée à 32 Kio ; le texte est affiché, jamais exécuté. Son contenu vient du dépôt et peut être trompeur : vérifiez le script avant de le lancer.

Pour lancer plusieurs scripts, cliquez sur leur case ou utilisez Espace. Le numéro indique leur ordre d’exécution ; désélectionner puis sélectionner à nouveau un script le place à la fin. La sélection est conservée en changeant de dossier ou de source. Cliquez sur « Lancer » ou appuyez sur `x` pour vérifier la liste et confirmer son exécution ; les flèches ou la molette permettent de parcourir une longue liste. « Vider » ou `c` efface la sélection.

L’option « Arrêter si erreur » est activée par défaut ; cliquez dessus ou utilisez `e` pour la modifier. Un code de sortie non nul, un échec de démarrage ou de téléchargement interrompt alors la série. Si l’option est désactivée, les scripts suivants sont lancés malgré l’erreur. Le résultat indique le nombre d’échecs ; la sélection reste disponible après l’exécution. L’annulation d’une demande d’authentification interrompt la série.

Les scripts `.sh` et `.ps1` ne sont exécutés qu’après confirmation, avec les droits de l’utilisateur courant. Les scripts locaux sont exécutés depuis leur emplacement d’origine ; les scripts distants sont téléchargés individuellement. Un script distant qui dépend d’autres fichiers du dépôt doit les récupérer lui-même. Les scripts `.sh` nécessitent Bash et les scripts `.ps1` nécessitent PowerShell.

Pour les dépôts HTTP protégés, les identifiants Basic sont demandés lors d’une réponse 401, restent en mémoire pendant la session et ne sont envoyés qu’en HTTPS (sauf sur localhost pour les tests).

## Développement

```bash
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo run
```

Sous Linux, `bash packaging/build-deb.sh` construit un paquet dans `dist/`. La CI produit des paquets Debian statiques pour amd64 et arm64. La préparation des installateurs, du dépôt APT signé et du Worker Cloudflare est décrite dans [docs/distribution.md](docs/distribution.md). La publication nécessite la configuration des accès et de la clé de signature.

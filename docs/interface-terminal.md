# Interface dans le terminal : audit et évolution

## Constat

MyEasyToolkit est une application Rust compilée, dont l'interface est dessinée avec Ratatui et les événements gérés avec Crossterm. Les scripts restent exécutés par Bash ou PowerShell. Les références choisies sont [Linutil](https://github.com/ChrisTitusTech/linutil) et [OpenCode](https://opencode.ai/docs/) : leur organisation et leur lisibilité servent d'inspiration, sans reprendre leur identité visuelle ni leur code.

L'interface initiale permet de naviguer à la souris et au clavier, mais présente plusieurs limites :

- les sources, le chemin, la liste et les actions ont une importance visuelle proche ;
- le nombre de scripts choisis est visible, mais leur ordre n'est pas consultable sur l'écran principal ;
- les longs chemins sont coupés à droite, ce qui peut masquer le dossier courant ;
- certains contrôles sont tronqués lorsque le terminal est étroit ;
- les zones cliquables sont liées à des coordonnées qu'il faut maintenir avec les libellés ;
- les couleurs et la police dépendent des capacités et réglages du terminal.

## Première évolution

1. Hiérarchiser les sources, l'emplacement, les fichiers et les actions avec des libellés cohérents et des bordures discrètes.
2. Afficher la sélection ordonnée et l'élément actif dans un panneau latéral sur les terminaux assez larges ; conserver la liste et les commandes essentielles en largeur réduite.
3. Garder visibles les extrémités des chemins longs et adapter les commandes de navigation aux fenêtres étroites.
4. Conserver les raccourcis, la souris, l'authentification, la confirmation et l'arrêt sur erreur. Utiliser principalement les couleurs de texte du terminal et tester les dispositions et les actions sur plusieurs tailles.

## Pistes ultérieures

Un filtrage des fichiers, une liste de sélection réorganisable et un système de thèmes pourraient être étudiés séparément. Les tests de lisibilité dans des terminaux clairs, à palette limitée et dans des environnements d'assistance restent nécessaires. La police et la taille des caractères sont contrôlées par le terminal, pas par MyEasyToolkit.

# Dépôts APT stable et de test

Le canal `testing` est préparé pour un dépôt distinct : il ne doit pas être activé sur les clients par défaut. Cette préparation ne publie aucun dépôt ni ne configure de secret de production.

Sous Linux, `MET_APT_SUITE=testing MET_APT_SIGNING_SUBKEY=EMPREINTE_TEST bash packaging/build-apt-repository.sh PAQUETS SORTIE EMPREINTE_PRINCIPALE` prépare le dépôt de test. La sous-clé de signature doit être indiquée par son empreinte complète, être rattachée à la clé principale fournie et être disponible dans le trousseau GnuPG de la CI de test. Le dépôt `stable` reste le comportement par défaut ; `MET_APT_SIGNING_SUBKEY` permet aussi d'y imposer explicitement sa sous-clé. Si plusieurs sous-clés privées de signature sont disponibles, le constructeur exige une sélection explicite, même pour `stable`. Conserver les secrets des CI de test et de production séparés. L'outil ne peut pas déterminer par lui-même si une sous-clé explicitement fournie est destinée à la production ou au test.

Chaque source APT doit disposer d'un fichier public de clés de confiance et épingler **l'empreinte exacte de sa propre sous-clé**, avec `signed-by` ; les noms `stable` et `testing` ne suffisent pas à séparer la confiance. Un même trousseau public peut contenir les deux sous-clés si chaque source limite l'empreinte autorisée. Le trousseau public doit contenir la clé principale et la liaison OpenPGP de la sous-clé ; ne jamais distribuer de clé privée.

Par exemple, après avoir obtenu et vérifié le trousseau et l'empreinte de test par un canal de confiance, une source destinée à une machine `amd64` aurait cette forme. L'adresse et l'empreinte ci-dessous sont des **emplacements à remplacer**, pas un dépôt publié :

```text
deb [arch=amd64 signed-by=/usr/share/keyrings/myeasytoolkit-testing.gpg,EMPREINTE_SOUS_CLE_TEST!] https://EXEMPLE.invalid/ testing main
```

Adapter `amd64` à l'architecture de la machine. La préparation des dépôts fournit le trousseau public du signataire ; son installation, son éventuel paquet dédié et ses mises à jour restent à définir avant publication.

La matrice `tests/compat-apt-prepare.sh` et `tests/compat-apt-client.sh` génère une clé RSA jetable et deux sous-clés. Elle construit chaque dépôt dans un trousseau de CI isolé ne contenant que sa sous-clé privée, puis vérifie les quatre couples : chaque dépôt accepte sa sous-clé et rejette l'autre. Ces tests incluent Debian 10 et 11 dans la CI. Leurs clés ne sont pas des clés de production.

Lors d'une rotation, un paquet de clés mis à jour ne remplace pas à lui seul l'empreinte épinglée dans une source APT. Préparer avant le changement la distribution de la nouvelle empreinte aux clients et tester les cas hors ligne et de compromission. APT ne télécharge pas automatiquement les révocations OpenPGP. Une machine où l'on active `testing` peut recevoir des versions de test selon les versions et priorités APT ; documenter et vérifier les préférences avant activation.

La publication, les emplacements HTTPS définitifs, le provisionnement des secrets CI et la migration des installations existantes restent à concevoir et valider séparément.

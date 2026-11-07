# Comparaison des clés de dépôts logiciels

Observations effectuées le 7 novembre 2026 à partir des clés publiques des éditeurs et, lorsqu'indiqué, de la vérification cryptographique d'un fichier `InRelease`. Elles portent sur les clés et dépôts précis cités, pas sur tous les produits ni toutes les signatures de chaque éditeur. La présence d'une sous-clé publique ne démontre pas à elle seule que la clé privée principale est hors ligne.

| Dépôt ou produit vérifié | Clé principale observée | Sous-clé et signature observées |
|---|---|---|
| [Google Chrome pour Linux](https://www.google.com/linuxrepositories/) | Clé de 2016 sans expiration publiée. | Plusieurs sous-clés de signature avec échéance ; l'`InRelease` stable vérifié utilise la sous-clé créée en 2025 et expirant en janvier 2028. Google décrit une rotation des sous-clés pour les RPM. |
| [Docker pour Ubuntu](https://docs.docker.com/engine/install/ubuntu/) | Clé de 2017 sans expiration publiée. | Une sous-clé de signature sans expiration ; l'`InRelease` Ubuntu noble vérifié est signé par cette sous-clé. |
| [Debian : clés d'archive](https://lists.debian.org/debian-devel-announce/2025/04/msg00001.html) | La principale d'archive Debian 13, créée en 2025, expire en 2035 ; celle de Debian 12 expire en 2031. | Les sous-clés de signature d'archive ont les mêmes échéances. L'`InRelease` Debian 13 vérifié comporte des signatures des sous-clés d'archive Debian 12 et 13, ainsi qu'une signature directe de la clé stable Debian 13. |
| [Proxmox VE 9](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf) | Clé Trixie créée en 2024, expirant en 2034. | Pas de sous-clé dans le fichier public observé ; l'`InRelease` vérifié est signé directement avec la principale. La clé a été récupérée en HTTPS ; l'`InRelease` a été récupéré en HTTP puis authentifié par sa signature, l'accès HTTPS au miroir ayant échoué sur une erreur de certificat. |
| [Microsoft Edge pour Linux](https://learn.microsoft.com/en-us/linux/packages) | Clé Microsoft de 2015 sans expiration publiée. | Aucune sous-clé dans le fichier public examiné ; l'`InRelease` Edge stable vérifié est signé directement avec la principale. |
| [HashiCorp pour Ubuntu](https://apt.releases.hashicorp.com/gpg) | Clé créée en septembre 2026, expirant en septembre 2031. | Aucune sous-clé dans le fichier public examiné ; l'`InRelease` Ubuntu noble vérifié est signé directement avec la principale. |
| [Red Hat, clé RPM release 2](https://access.redhat.com/security/team/key) | Clé de 2009 sans expiration dans la clé publique observée. | Aucune sous-clé dans ce fichier public. Red Hat la documente comme clé de signature de produits ; aucun RPM n'a été vérifié lors de cet audit. Red Hat publie également des clés de secours distinctes. |

## Enseignements pour MyEasyToolkit

- Les pratiques diffèrent : aucune durée, ni architecture à une ou plusieurs clés, ne fait l'unanimité.
- Une clé principale sans expiration et une sous-clé de signature de trois ans constituent un choix cohérent avec les préférences exprimées par William ; sauvegarde, surveillance et procédure de révocation restent nécessaires.
- Une échéance peut être modifiée avec la clé principale sans changer son empreinte. La clé publique actualisée doit toutefois être distribuée aux clients concernés. Une expiration n'implique pas automatiquement de créer une nouvelle paire de clés ni de révoquer l'ancienne.
- Si une sous-clé change ou est révoquée, l'empreinte principale peut rester stable, mais les clients doivent recevoir et appliquer un trousseau public actualisé. La sécurité et la disponibilité du mécanisme de mise à jour restent à tester sur Debian et Ubuntu.
- La clé MyEasyToolkit de production nouvellement créée n'a pas encore servi à signer le dépôt public. Au 7 novembre 2026, elle est limitée à la certification et expire le 6 novembre 2031 ; aucune sous-clé n'est encore présente. La suppression de son échéance et la création de la sous-clé restent à réaliser avec William.

[GnuPG : gestion des clés et modification d'expiration](https://gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html) · [Debian : introduction et distribution anticipée des clés d'archive](https://lists.debian.org/debian-devel-announce/2025/04/msg00001.html) · [Debian : authentification des dépôts](https://manpages.debian.org/bookworm/apt/apt-secure.8.en.html).

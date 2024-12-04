#!/bin/bash

# Hash SHA-256 attendu du mot de passe
DATA_URL=$(echo -n "aHR0cHM6Ly9tZWRpYS5naXRodWJ1c2VyY29udGVudC5jb20vbWVkaWEvd2lsbGlhbWJvZ2xpZXR0aS9NeUVhc3lUb29sa2l0L3JlZnMvaGVhZHMvbWFpbi9tYWNPUy9kYXRhLnppcA==" | base64 --decode)
USER_KEY=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3VzZXIua2V5" | base64 --decode)
ADMIN_KEY=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL2FkbWluLmtleQ==" | base64 --decode)
MAX_ATTEMPTS=3  # Limiter les tentatives de mot de passe à 3
attempt=1

# Demander le mot de passe avec osascript
get_password() {
    PASSWORD=$(osascript -e 'display dialog "Entrez le mot de passe pour accéder au menu :" default answer "" with hidden answer buttons {"OK"} default button "OK" with icon caution' -e 'text returned of result' 2>/dev/null)
}

# Afficher un message d'alerte avec le nombre de tentatives restantes
show_alert() {
    remaining_attempts=$((MAX_ATTEMPTS - attempt))
    osascript -e "display dialog \"Mot de passe incorrect. Il vous reste $remaining_attempts tentative(s).\" with icon caution buttons {\"OK\"} default button \"OK\""
}

# Vérifier le hash du mot de passe
verify_password() {
    # Calculer le hash SHA-256 du mot de passe saisi
    PASSWORD_HASH=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')
    unset PASSWORD  # Supprime la variable pour des raisons de sécurité
    if [[ "$PASSWORD_HASH" == "$CORRECT_HASH" ]]; then
        echo "Mot de passe correct."
    else
        show_alert  # Affiche l'alerte en cas de mauvais mot de passe
        return 1
    fi
}

# Variables
MEO_DIR="$HOME/MyEasyOptic"
INSTALL_DIR="$(pwd)" # Le répertoire actuel où se trouve le script
TMP_DATA="$INSTALL_DIR/.tmp" # Répertoire temporaire pour l'extraction
ZIP_FILE="$INSTALL_DIR/data.zip" # Fichier ZIP à extraire

# Vérifier que le fichier ZIP existe
if [ ! -f "$ZIP_FILE" ]; then
  echo "Le fichier $ZIP_FILE n'existe pas."
  osascript -e "display dialog \"Le fichier $ZIP_FILE n'existe pas.\" with icon caution buttons {\"OK\"} default button \"OK\""
  exit 1
fi

# Créer le répertoire temporaire
mkdir -p "$TMP_DATA"

# Extraire le fichier ZIP dans le répertoire temporaire
unzip "$ZIP_FILE" -d "$TMP_DATA"

sudo chmod -x $TMP_DATA/data/scripts/install* $TMP_DATA/data/scripts/uninstall* $TMP_DATA/data/scripts/run.sh $TMP_DATA

cp $TMP_DATA/data/scripts/run.sh $TMP_DATA

# Fonction pour purger TMP_DATA
cleanup_TMP_DATA() {
  echo "Purge du répertoire temporaire..."
  rm -rf "$TMP_DATA"
  if [ $? -eq 0 ]; then
    echo "Purge réussie."
  else
    echo "Erreur lors de la purge du répertoire temporaire."
    osascript -e "display dialog \"Erreur lors de la purge du répertoire temporaire.\" with icon caution buttons {\"OK\"} default button \"OK\""
  fi
}

# Désactiver les vérifications de signature & XprotectService
sudo spctl --master-disable
spctl developer-mode enable-terminal

# Exécuter run.sh
sudo $TMP_DATA/run.sh

# Appeler la fonction de nettoyage
cleanup_TMP_DATA

# Ré-activer les vérifications de signature & XprotectService
sudo spctl --master-enable

exit 0
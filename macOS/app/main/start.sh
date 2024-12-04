#!/bin/bash

# Vérifie si cURL ou wget est installé
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    echo "Erreur : cURL ou wget est requis pour exécuter ce script."
    osascript -e "display dialog \"Erreur : cURL ou wget est requis pour exécuter ce script.\" with icon caution buttons {\"OK\"} default button \"OK\""
    exit 1
fi

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
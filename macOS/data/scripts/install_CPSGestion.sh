#!/bin/bash

# Variables
INSTALL_DIR="$(pwd)/CPS_Gestion" # Le répertoire actuel où se trouve le script
TMP_DIR="$INSTALL_DIR/tmp" # Répertoire temporaire pour l'extraction
ZIP_FILE="$INSTALL_DIR/data.zip" # Fichier ZIP à extraire
APP_FILE="CPSGestion.app"
BOM_FILE="fr.asip.esante.cpsgestion.dev.bom"
PLIST_FILE="fr.asip.esante.cpsgestion.dev.plist"
DEST_APP="/Applications/$APP_FILE"
DEST_RECEIPTS="/var/db/receipts"

# Vérifier que le fichier ZIP existe
if [ ! -f "$ZIP_FILE" ]; then
  echo "Le fichier $ZIP_FILE n'existe pas."
  exit 1
fi

# Créer le répertoire temporaire
mkdir -p "$TMP_DIR"

# Extraire le fichier ZIP dans le répertoire temporaire
unzip "$ZIP_FILE" -d "$TMP_DIR"

# Copier le fichier .app dans /Applications
if [ -d "$TMP_DIR/data/$APP_FILE" ]; then
  echo "Copie de $APP_FILE dans /Applications..."
  sudo cp -R "$TMP_DIR/data/$APP_FILE" "$DEST_APP"
else
  echo "Erreur : $APP_FILE n'a pas été trouvé dans l'archive."
  exit 1
fi

# Copier les fichiers .bom et .plist dans /var/db/receipts
if [ -f "$TMP_DIR/data/$BOM_FILE" ]; then
  echo "Copie de $BOM_FILE dans /var/db/receipts..."
  sudo cp "$TMP_DIR/data/$BOM_FILE" "$DEST_RECEIPTS"
else
  echo "Erreur : $BOM_FILE n'a pas été trouvé dans l'archive."
  exit 1
fi

if [ -f "$TMP_DIR/data/$PLIST_FILE" ]; then
  echo "Copie de $PLIST_FILE dans /var/db/receipts..."
  sudo cp "$TMP_DIR/data/$PLIST_FILE" "$DEST_RECEIPTS"
else
  echo "Erreur : $PLIST_FILE n'a pas été trouvé dans l'archive."
  exit 1
fi

# Nettoyer le répertoire temporaire
echo "Nettoyage du répertoire temporaire..."
rm -rf "$TMP_DIR"

echo "Installation terminée avec succès."
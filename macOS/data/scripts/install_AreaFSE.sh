#!/bin/sh
#mise en place SV sous MAC création 08/06/2023

#Ajout 27/09/2024 - Mise en place CPS Gestion sans passer par l'AppStore
# Variables
INSTALL_DIR="$(pwd)/CPS_Gestion" # Le répertoire actuel où se trouve le script
TMP_DIR="$INSTALL_DIR/tmp" # Répertoire temporaire pour l'extraction
ZIP_FILE="$INSTALL_DIR/data.zip" # Fichier ZIP à extraire
APP_FILE="CPSGestion.app"
BOM_FILE="fr.asip.esante.cpsgestion.dev.bom"
PLIST_FILE="fr.asip.esante.cpsgestion.dev.plist"
DEST_APP="/Applications/$APP_FILE"
DEST_RECEIPTS="/var/db/receipts"

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
#Fin de l'installation CPS Gestion

#Début installation AREASV
killall wrapper
killall MyEasyLocalService-Start
sudo ./uninstall_AreaFSE.sh
sudo ./uninstall_Cryptolib.sh
sudo ./uninstall_GALSS.sh

#installation des paquetages utiles
sudo installer -pkg Package\ Applications/1-OpenJDK8U-jre_x64_mac_hotspot_8u222b10.pkg -target /Applications
sudo installer -pkg Package\ Applications/2-CryptolibCPS-5.2.1.pkg -target /Applications
sudo installer -pkg Package\ Applications/3-MyEasyLocalService-installer-1.31.pkg -target /Applications

sudo unzip -o Package\ Applications/AreaFSE_v3.00.1.9.zip -d /Applications
sudo chmod -R 777 /Applications/AreaFse

open /Applications/MyEasyLocalService-Start.app
open /Applications/Lancer\ AreaFse.app

exit 0
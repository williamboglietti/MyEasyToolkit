#!/bin/bash

# Définition des constantes
DATA_URL=$(echo -n "aHR0cHM6Ly9tZWRpYS5naXRodWJ1c2VyY29udGVudC5jb20vbWVkaWEvd2lsbGlhbWJvZ2xpZXR0aS9NeUVhc3lUb29sa2l0L3JlZnMvaGVhZHMvbWFpbi9tYWNPUy9kYXRhLnppcA==" | base64 --decode)
SHA256_DATA=$(curl -s $(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL2RhdGEuc2hhMjU2" | base64 --decode))
USER_KEY=$(curl -s $(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3VzZXIua2V5" | base64 --decode))
ADMIN_KEY=$(curl -s $(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL2FkbWluLmtleQ==" | base64 --decode))
MAX_ATTEMPTS=3
attempt=1

# Variables pour l'installation
INSTALL_DIR="$HOME/MyEasyOptic"
TMP_DATA="$INSTALL_DIR/.tmp"
ZIP_FILE="$INSTALL_DIR/data.zip"

# Fonction pour demander le mot de passe via osascript
get_password() {
    PASSWORD=$(osascript -e 'display dialog "Entrez le mot de passe pour accéder au menu :" default answer "" with hidden answer buttons {"OK"} default button "OK" with icon caution' -e 'text returned of result' 2>/dev/null)
}

# Fonction pour afficher un message d'alerte
show_alert() {
    remaining_attempts=$((MAX_ATTEMPTS - attempt))
    osascript -e "display dialog \"Mot de passe incorrect. Il vous reste $remaining_attempts tentative(s).\" with icon caution buttons {\"OK\"} default button \"OK\""
}

# Vérifier le hash du mot de passe
verify_password() {
    PASSWORD_HASH=$(echo -n "$PASSWORD" | shasum -a 256 | awk '{print $1}')
    unset PASSWORD  # Supprime la variable pour des raisons de sécurité

    if [[ "$PASSWORD_HASH" == "$USER_KEY" ]]; then
        echo "Accès utilisateur accordé."
        MENU_TYPE="USER"
        return 0
    elif [[ "$PASSWORD_HASH" == "$ADMIN_KEY" ]]; then
        echo "Accès administrateur accordé."
        MENU_TYPE="ADMIN"
        return 0
    else
        show_alert
        return 1
    fi
}

# Fonction pour télécharger le fichier data.zip depuis DATA_URL
download_data_zip() {
    echo "Téléchargement des fichiers supplémentaires..."
    echo "Veuillez patienter..."
    curl -o "$ZIP_FILE" "$DATA_URL"
    if [ $? -eq 0 ]; then
        echo "Téléchargement réussi."
    else
        echo "Erreur lors du téléchargement du fichier data.zip."
        osascript -e "display dialog \"Erreur lors du téléchargement du fichier data.zip.\" with icon caution buttons {\"OK\"} default button \"OK\""
        exit 1
    fi
}

# Vérification du hash SHA256 du fichier téléchargé
verify_sha256_zip() {
    echo -e "Vérification du hash SHA256..."
    local calculated_sha256
    calculated_sha256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')

    if [[ "$calculated_sha256" != "$SHA256_DATA" ]]; then
        echo -e "Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu."
        osascript -e "display dialog \"Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu.\" with icon caution buttons {\"OK\"} default button \"OK\""
        cleanup_TMP_DATA
        exit 1
    fi
    echo -e "Le hash SHA256 est valide."
}

# Fonction pour afficher le menu utilisateur
user_menu() {
    osascript -e 'display dialog "Bienvenue dans le menu utilisateur.\nOptions disponibles :\n1. Voir les fichiers.\n2. Quitter." buttons {"OK"} default button "OK" with icon note'
}

# Fonction pour afficher le menu administrateur
admin_menu() {
    osascript -e 'display dialog "Bienvenue dans le menu administrateur.\nOptions disponibles :\n1. Voir les fichiers.\n2. Gérer les utilisateurs.\n3. Quitter." buttons {"OK"} default button "OK" with icon note'
}

# Gestion des tentatives de mot de passe
while [ $attempt -le $MAX_ATTEMPTS ]; do
    get_password
    if verify_password; then
        break
    fi
    attempt=$((attempt + 1))
done

if [ $attempt -gt $MAX_ATTEMPTS ]; then
    osascript -e 'display dialog "Vous avez dépassé le nombre maximal de tentatives." with icon stop buttons {"OK"} default button "OK"'
    exit 1
fi

# Fonction pour vérifier si data.zip existe déjà et si son hash est correct
check_and_download_data_zip() {
    if [ -f "$ZIP_FILE" ]; then
        echo "Fichier data.zip trouvé. Vérification du SHA256..."

        # Calculer le hash local du fichier
        local calculated_sha256
        calculated_sha256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')

        # Comparer les deux hashes
        if [[ "$calculated_sha256" == "$SHA256_DATA" ]]; then
            echo "Le fichier data.zip est déjà à jour. Pas de téléchargement nécessaire."
            return 0
        else
            echo "Une nouvelle version de data.zip est disponible. Suppression et téléchargement de la nouvelle version..."
            rm -f "$ZIP_FILE"
        fi
    fi

    # Télécharger le fichier data.zip
    download_data_zip
}

# Télécharger ou vérifier le fichier data.zip après une authentification réussie
check_and_download_data_zip

# Vérification du hash SHA256 du zip téléchargé
verify_sha256_zip

# Créer le répertoire temporaire et extraire les fichiers
mkdir -p "$TMP_DATA"
unzip "$ZIP_FILE" -d "$TMP_DATA"
chmod -x $TMP_DATA/data/scripts/install* $TMP_DATA/data/scripts/uninstall* $TMP_DATA/data/scripts/run.sh $TMP_DATA
cp $TMP_DATA/data/scripts/run.sh $TMP_DATA

# Afficher le menu en fonction des privilèges
if [ "$MENU_TYPE" == "USER" ]; then
    user_menu
elif [ "$MENU_TYPE" == "ADMIN" ]; then
    admin_menu
fi

# Nettoyage des fichiers temporaires
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
# sudo $TMP_DATA/run.sh

# Ré-activer les vérifications de signature & XprotectService
sudo spctl --master-enable

# Appeler la fonction de nettoyage
cleanup_TMP_DATA

exit 0
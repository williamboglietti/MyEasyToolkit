#!/bin/bash

# Variables
REMOTE_SCRIPT_URL=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3N0YXJ0LnNo" | base64 --decode)
SHA256_URL=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3N0YXJ0LnNoYTI1Ng==" | base64 --decode)
TMP_DIR="/tmp/MyEasyToolkit"  # Répertoire temporaire pour l'extraction du script
TEMP_FILE="$TMP_DIR/start.sh"  # Fichier temporaire pour le script téléchargé

# Codes de couleur
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m" # Pas de couleur

# Activer le mode de gestion des erreurs
set -euo pipefail
trap "echo -e '${RED}Erreur détectée. Nettoyage en cours...${NC}'; cleanup; exit 1" ERR

# Fonction de message d'erreur avec dialogue OS
show_error_dialog() {
    local message=$1
    osascript -e "display dialog \"$message\" with icon caution buttons {\"OK\"} default button \"OK\""
}

# Fonction de nettoyage
cleanup() {
    echo -e "${GREEN}Nettoyage des fichiers temporaires...${NC}"
    rm -rf "$TMP_DIR" || { show_error_dialog "Impossible de supprimer le dossier temporaire $TMP_DIR."; exit 1; }
    echo -e "${GREEN}Nettoyage terminé !${NC}"
}

# Vérifier la connexion internet
check_internet_connection() {
    echo -e "${GREEN}Vérification de la connexion internet...${NC}"
    if ! curl -s --head --request GET "http://www.google.com" | grep "200 OK" > /dev/null; then
        echo -e "${RED}Erreur : Impossible de se connecter à Internet.${NC}"
        show_error_dialog "Erreur : Impossible de se connecter à Internet. Vérifiez votre connexion réseau."
        exit 1
    fi
    echo -e "${GREEN}Connexion internet validée.${NC}"
}

# Vérification du hash SHA256 du fichier téléchargé
verify_sha256() {
    echo -e "${GREEN}Vérification du hash SHA256...${NC}"
    expected_sha256=$(curl -fsSL "$SHA256_URL") || { show_error_dialog "Erreur : Impossible de télécharger le fichier SHA256."; exit 1; }
    local calculated_sha256
    calculated_sha256=$(shasum -a 256 "$TEMP_FILE" | awk '{ print $1 }')

    echo -e "${GREEN}Hash calculé : ${calculated_sha256}${NC}"
    echo -e "${GREEN}Hash attendu : ${expected_sha256}${NC}"

    if [[ "$calculated_sha256" != "$expected_sha256" ]]; then
        echo -e "${RED}Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu.${NC}"
        show_error_dialog "Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu."
        cleanup
        exit 1
    fi
    echo -e "${GREEN}Le hash SHA256 est valide.${NC}"
}

# Vérifier si le dossier temporaire existe, sinon le créer
echo -e "${GREEN}Préparation du système en cours...${NC}"
mkdir -p "$TMP_DIR" || { show_error_dialog "Impossible de créer le dossier temporaire $TMP_DIR."; cleanup; exit 1; }
echo -e "${GREEN}Initialisation effectuée.${NC}"

# Vérification de la connexion internet avant de procéder au téléchargement
check_internet_connection

# Fonction pour télécharger le script
download_script() {
    echo -e "${GREEN}Téléchargement des fichiers requis...${NC}"
    if command -v curl &>/dev/null; then
        curl -fsSL -o "$TEMP_FILE" "$REMOTE_SCRIPT_URL"
    elif command -v wget &>/dev/null; then
        wget -q -O "$TEMP_FILE" "$REMOTE_SCRIPT_URL"
    else
        echo -e "${RED}Erreur : ni curl ni wget n'est disponible pour télécharger le script.${NC}"
        show_error_dialog "Erreur : ni curl ni wget n'est disponible pour télécharger le script."
        cleanup
        exit 1
    fi
}

# Télécharger le script
download_script

# Vérification du téléchargement
if [[ ! -f "$TEMP_FILE" ]]; then
    echo -e "${RED}Erreur : Impossible de télécharger le script.${NC}"
    show_error_dialog "Erreur : Impossible de télécharger le script."
    cleanup
    exit 1
fi

echo -e "${GREEN}Téléchargement réussi. Vérification des fichiers...${NC}"

# Vérification du hash SHA256 du fichier téléchargé
verify_sha256

echo -e "${GREEN}Vérification des fichiers réussie. Vérification des permissions...${NC}"

# Donner des permissions d'exécution au script téléchargé
chmod +x "$TEMP_FILE" || { show_error_dialog "Impossible de définir les permissions pour le fichier $TEMP_FILE."; cleanup; exit 1; }

echo -e "${GREEN}Démarrage de MyEasyToolkit...${NC}"
sudo bash "$TEMP_FILE"
SCRIPT_EXIT_CODE=$?

# Vérifier le code de retour du script
if [[ $SCRIPT_EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}MyEasyToolkit a terminé avec succès.${NC}"
else
    echo -e "${RED}Erreur : MyEasyToolkit a échoué avec le code de retour $SCRIPT_EXIT_CODE.${NC}"
    show_error_dialog "Erreur : MyEasyToolkit a échoué avec le code de retour $SCRIPT_EXIT_CODE."
    cleanup
    exit 1
fi

echo -e "${GREEN}Arrêt de MyEasyToolkit.${NC}"

# Appeler la fonction de nettoyage en fin de script
cleanup

exit 0
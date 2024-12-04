#!/bin/bash

# Variables
REMOTE_SCRIPT_URL=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3N0YXJ0LnNo" | base64 --decode)
SHA256_URL=$(echo -n "aHR0cHM6Ly9teWVhc3l0b29sa2l0Lm92aC9tYWluL3N0YXJ0LnNoYTI1Ng==" | base64 --decode)
TMP_DIR="/tmp/MyEasyToolkit"  # Répertoire temporaire pour l'extraction du script
TEMP_FILE="$TMP_DIR/start.sh"  # Fichier temporaire pour le script téléchargé

# Activer le mode de gestion des erreurs
set -euo pipefail
trap "echo -e 'Erreur détectée. Nettoyage en cours...'; cleanup; exit 1" ERR

# Fonction de message d'erreur avec dialogue OS
show_error_dialog() {
    local message=$1
    osascript -e "display dialog \"$message\" with icon caution buttons {\"OK\"} default button \"OK\""
}

# Fonction de nettoyage
cleanup() {
    echo -e "Nettoyage des fichiers temporaires..."
    rm -rf "$TMP_DIR" || { show_error_dialog "Impossible de supprimer le dossier temporaire $TMP_DIR."; exit 1; }
    echo -e "Nettoyage terminé !"
}

# Vérifier la connexion internet
check_internet_connection() {
    echo -e "Vérification de la connexion internet..."
    if ! curl -s --head --request GET "http://www.google.com" | grep "200 OK" > /dev/null; then
        echo -e "Erreur : Impossible de se connecter à Internet."
        show_error_dialog "Erreur : Impossible de se connecter à Internet. Vérifiez votre connexion réseau."
        exit 1
    fi
    echo -e "Connexion internet validée."
}

# Vérification du hash SHA256 du fichier téléchargé
verify_sha256() {
    echo -e "Vérification du hash SHA256..."
    expected_sha256=$(curl -fsSL "$SHA256_URL") || { show_error_dialog "Erreur : Impossible de télécharger le fichier SHA256."; exit 1; }
    local calculated_sha256
    calculated_sha256=$(shasum -a 256 "$TEMP_FILE" | awk '{ print $1 }')

    echo -e "Hash calculé : ${calculated_sha256}"
    echo -e "Hash attendu : ${expected_sha256}"

    if [[ "$calculated_sha256" != "$expected_sha256" ]]; then
        echo -e "Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu."
        show_error_dialog "Erreur : Le hash SHA256 du fichier téléchargé ne correspond pas au hash attendu."
        cleanup
        exit 1
    fi
    echo -e "Le hash SHA256 est valide."
}

# Vérifier si le dossier temporaire existe, sinon le créer
echo -e "Préparation du système en cours..."
mkdir -p "$TMP_DIR" || { show_error_dialog "Impossible de créer le dossier temporaire $TMP_DIR."; cleanup; exit 1; }
echo -e "Initialisation effectuée."

# Vérification de la connexion internet avant de procéder au téléchargement
check_internet_connection

# Fonction pour télécharger le script
download_script() {
    echo -e "Téléchargement des fichiers requis..."
    if command -v curl &>/dev/null; then
        curl -fsSL -o "$TEMP_FILE" "$REMOTE_SCRIPT_URL"
    elif command -v wget &>/dev/null; then
        wget -q -O "$TEMP_FILE" "$REMOTE_SCRIPT_URL"
    else
        echo -e "Erreur : ni curl ni wget n'est disponible pour télécharger le script."
        show_error_dialog "Erreur : ni curl ni wget n'est disponible pour télécharger le script."
        cleanup
        exit 1
    fi
}

# Télécharger le script
download_script

# Vérification du téléchargement
if [[ ! -f "$TEMP_FILE" ]]; then
    echo -e "Erreur : Impossible de télécharger le script."
    show_error_dialog "Erreur : Impossible de télécharger le script."
    cleanup
    exit 1
fi

echo -e "Téléchargement réussi. Vérification des fichiers..."

# Vérification du hash SHA256 du fichier téléchargé
verify_sha256

echo -e "Vérification des fichiers réussie. Vérification des permissions..."

# Donner des permissions d'exécution au script téléchargé
chmod +x "$TEMP_FILE" || { show_error_dialog "Impossible de définir les permissions pour le fichier $TEMP_FILE."; cleanup; exit 1; }

echo -e "Démarrage de MyEasyToolkit..."
$TEMP_FILE
SCRIPT_EXIT_CODE=$?

# Vérifier le code de retour du script
if [[ $SCRIPT_EXIT_CODE -eq 0 ]]; then
    echo -e "MyEasyToolkit a terminé avec succès."
else
    echo -e "Erreur : MyEasyToolkit a échoué avec le code de retour $SCRIPT_EXIT_CODE."
    show_error_dialog "Erreur : MyEasyToolkit a échoué avec le code de retour $SCRIPT_EXIT_CODE."
    cleanup
    exit 1
fi

echo -e "Arrêt de MyEasyToolkit."

# Appeler la fonction de nettoyage en fin de script
cleanup

exit 0
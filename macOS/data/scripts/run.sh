#!/bin/bash

# Hash SHA-256 attendu du mot de passe "maceasyoptic"
CORRECT_HASH="1efc65049be6d84b51c47bab6fdd682289e0cf8037bcd5ac14b09e9d2e5ac0e7"
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
        echo "Mot de passe correct. Accès autorisé."
    else
        show_alert  # Affiche l'alerte en cas de mauvais mot de passe
        return 1
    fi
}

# Fonction pour afficher le menu
show_menu() {
    echo -e "\033[1mChoisissez une option :\033[0m"
    echo -e "\033[1;32m1\033[0m - Installation AreaFSE"
    echo -e "\033[1;32m2\033[0m - Désinstallation AreaFSE"
    echo -e "\033[1;32m3\033[0m - Diagnostique"
    echo -e "\033[1;32m4\033[0m - Quitter"
    echo -n "Entrez votre choix : "
}

# Fonction pour chaque option
install_areafse() {
    echo "Installation d'AreaFSE..."
    # Ajoutez ici la commande pour installer AreaFSE
}

uninstall_areafse() {
    echo "Désinstallation d'AreaFSE..."
    # Ajoutez ici la commande pour désinstaller AreaFSE
}

diagnose() {
    echo "Exécution du diagnostique..."
    # Ajoutez ici la commande pour diagnostiquer AreaFSE ou autre
}

# Boucle pour demander le mot de passe avec un nombre limité de tentatives
while [[ $attempt -le $MAX_ATTEMPTS ]]; do
    get_password
    if verify_password; then
        break
    fi
    echo "Tentative $attempt/$MAX_ATTEMPTS"
    ((attempt++))
    if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
        echo "Accès refusé. Trop de tentatives."
        exit 1
    fi
done

# Boucle principale du menu
while true; do
    show_menu
    read -r choice
    case $choice in
        1) install_areafse ;;
        2) uninstall_areafse ;;
        3) diagnose ;;
        4) echo "Quitter..."; exit 0 ;;
        *) echo "Option invalide. Veuillez choisir une option valide (1-4)." ;;
    esac
    echo
done
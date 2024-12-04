#!/bin/sh -f

# Arrêter le processus galsvosx
sudo killall -9 galsvosx

# Daemon FISS
sudo launchctl bootout system /Library/LaunchDaemons/fr.sesamvitale.fiss.plist
sudo rm -f "/Library/LaunchDaemons/fr.sesamvitale.fiss.plist"

# Suppression des frameworks galss
sudo rm -rf "/Library/Frameworks/galclosx.framework/"
sudo rm -rf "/Library/Frameworks/galinosx.framework/"
sudo rm -rf "/Library/Frameworks/galssosx.framework/"
sudo rm -rf "/Library/Frameworks/pcscosx.framework/"
sudo rm -rf "/Library/Frameworks/pssinosx.framework/"

# Suppression des logs
sudo rm -rf "/Library/Logs/santesocial"

# Suppression repertoires santesocial & GALSS + fichers de configurations
sudo rm -rf "/Library/Application Support/santesocial"
sudo rm -rf "/Library/Application Support/Galss"
sudo rm -rf "/Library/Preferences/santesocial"
sudo rm -rf "/Library/Preferences/galss.ini"
sudo rm -rf "/Library/Preferences/io_comm.ini"

# Suppression receipts
sudo rm -rf "/Library/Receipts/galss.pkg"
sudo rm -rf "/var/db/receipts/fr.sesamvitale.galss.*"

sudo pkgutil --forget fr.sesamvitale.galss.pkg
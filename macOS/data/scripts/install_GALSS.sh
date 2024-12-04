#!/bin/sh

sudo killall -9 wrapper
sudo killall -9 MyEasyLocalService-Start
sudo killall -9 galsvosx
pkill -f "Lancer AreaFse.app"

sudo ./uninstall_GALSS.sh

#installation des paquetages utiles
sudo installer -pkg Package\ Applications/4-Galss_3.43.02.pkg -target /Applications
echo Initialisation du GALSS en cours...
sleep 5
echo Lancement AreaFSE en cours...
sleep 3
open /Applications/Lancer\ AreaFse.app
echo Configuration AreaFSE en cours...
sleep 5
echo Lancement du MyEasyLocalService en cours...
sleep 3
open /Applications/MyEasyLocalService-Start.app
sleep 5
echo Installation terminée !

exit 0
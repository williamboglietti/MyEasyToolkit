#!/bin/sh

pkill -f "Lancer AreaFse.app"
sudo killall -9 galsvosx
sudo killall -9 java

open /Applications/Arreter\ AreaFse.app

#suppression des anciennes version d'AreaSV
sudo rm -rf "/Applications/Lancer AreaFse.app"
sudo rm -rf "/Applications/Arreter AreaFse.app"
sudo rm -rf "/Applications/AreaFSE" "/Applications/AreaF*"
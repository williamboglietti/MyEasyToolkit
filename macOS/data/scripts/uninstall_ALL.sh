#!/bin/sh

sudo ./uninstall_AreaFSE.sh
sudo ./uninstall_amelipro.sh
sudo ./uninstall_Cryptolib.sh
sudo ./uninstall_diagAM.sh
sudo ./uninstall_GALSS.sh
sudo ./uninstall_SrvSVCNAM.sh
sudo ./uninstall_MELS.sh

#Suppression GALSS et CPS Gestion
cd /Library/Application\ Support/Galss
./uninstall.sh

#suppression des fichiers résiduels si existent
rm -rf /Library/Application\ Support/santesocial
rm -rf /Library/Application\ Support/Galss
rm -f /Library/Preferences/galss.ini
rm -f /Library/Preferences/io_comm.ini
rm -f /Library/Preferences/DICO-FR.GIP
rm -f /Library/Frameworks/api.lec.framework
rm -f /Library/Frameworks/sedica.framework
rm -f /Library/Frameworks/cpsosx.framework
rm -f /Library/Frameworks/galclosx.framework
rm -f /Library/Frameworks/galinosx.framework
rm -f /Library/Frameworks/galssosx.framework
rm -f /Library/Frameworks/pcsosx.framework
rm -f /Library/Frameworks/pssinosx.framework
rm -f /Library/Frameworks/sscasosx.framework
rm -f /Library/Frameworks/iocomcnf
rm -f /Library/Frameworks/api_lec.framework
rm -f /Library/Frameworks/api_lec.ini
rm -f /Library/Frameworks/libapi_lec.dylib
rm -f /Library/Frameworks/pdt-cdc-011.csv
rm -f /Library/Frameworks/sedica.ini
rm -f /Library/Frameworks/tablebin.hab
rm -f /Library/Frameworks/tablebin.lec

#suppression des anciennes app lcv detect et cps gestion du finder
rm -rf /Applications/cpgesosx.app
rm -rf /Applications/LCVdetect.app
rm -rf /Applications/USB*.app
#suppression de tout ce qui est Area
rm -rf /Applications/AreaFSE /Applications/AreaF*

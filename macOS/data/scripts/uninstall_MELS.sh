#!/bin/sh

curl 'http://localhost:'$((grep ^port= ~/.MyEasyLocalService/config.properties 2> /dev/null || echo 'port=9000') | cut -d'=' -f2)'/stop?requete=meoinstaller'

killall wrapper
killall MyEasyLocalService-Start

#suppression des anciennes version du MyEasyLocalService
sudo rm -rf /Applications/MyEasyLocalService-Start.app
sudo rm -rf /Applications/MyEasyLocalService-Stop.app
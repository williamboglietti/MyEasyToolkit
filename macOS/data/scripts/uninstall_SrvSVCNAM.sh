#!/bin/sh

exec > /tmp/srvsvcnam_uninstall_log_file.txt 2>&1


function delete_certificates {

#définition des variables nécessaires à l'exécution de la commande
nomVieuxCertif='127.0.0.1 - CNAMTS'
nomVieuxCertif2='127.0.0.1'
nomCertif='AC-SRVSVCNAM'
nomCertif2='AC-SRVSVCNAM - GIE-SESAM-VITALE'
nomCertifTest='AC-SRVSVCNAM-DQI'
nomNouveauCertif='AC-SRVSVCNAM-256'

#version precedente cd "$dossier"
#on complète le chemin vers la bdd des certificats du profil Firefox de l'utilisateur
#version precedente cheminProfileCourant="${cheminProfiles}/$dossier"

if [[ "$1" == *cert9.db* ]]
then
echo "cas cert9"
namespace="sql:" 
else
echo "cas cert8"
namespace=""
fi

cheminProfileCourant=$(dirname "$1")

#suppression de l'ancien certificat, s'il existe (3 possibilites)
LD_LIBRARY_PATH=. ./certutil -D -n "${nomVieuxCertif}" -d "$namespace""${cheminProfileCourant}"
LD_LIBRARY_PATH=. ./certutil -D -n "${nomVieuxCertif2}" -d "$namespace""${cheminProfileCourant}"
LD_LIBRARY_PATH=. ./certutil -D -n "${nomCertif}" -d "$namespace""${cheminProfileCourant}"
LD_LIBRARY_PATH=. ./certutil -D -n "${nomCertif2}" -d "$namespace""${cheminProfileCourant}"
LD_LIBRARY_PATH=. ./certutil -D -n "${nomCertifTest}" -d "$namespace""${cheminProfileCourant}"

echo On va passer la commande LD_LIBRARY_PATH=. ./certutil -D -n "${nomNouveauCertif}" -d "$namespace""${cheminProfileCourant}"
LD_LIBRARY_PATH=. ./certutil -D -n "${nomNouveauCertif}" -d "$namespace""${cheminProfileCourant}"
echo On a passé la commande LD_LIBRARY_PATH=. ./certutil -D -n "${nomNouveauCertif}" -d "$namespace""${cheminProfileCourant}"

}




#TRAITEMENTS COMMUNS A TOUS LES UTILISATEURS
#-------------------------------------------

# Daemon SRVSVCNAM
if [ -f "/Library/LaunchAgents/org.cnamts.srvsvcnam.launchd.plist" ]; then
sudo launchctl unload /Library/LaunchAgents/org.cnamts.srvsvcnam.launchd.plist
sudo rm -f /Library/LaunchAgents/org.cnamts.srvsvcnam.launchd.plist
fi

# Arret du serveur
for X in `ps acx | grep -i SrvSVcnam | awk {'print $1'}`;
do
sudo kill $X;
done


sudo rm -rf "/Library/Application Support/SrvSVcnam"
sudo rm -rf "/Library/Application Support/santesocial/SrvSVcnam"
sudo rm -rf "/Applications/SrvSVcnam_Lanceur.app"
sudo rm -rf "/Applications/SrvSVcnam_Moniteur.app"
sudo rm -rf "/Library/PreferencePanes/Composant SrvSVCNAM.prefPane"


# Suppression des certificats du trousseau
sudo /usr/bin/security delete-certificate -c "127.0.0.1" /Library/Keychains/System.keychain
sudo /usr/bin/security delete-certificate -c "AC-SRVSVCNAM" /Library/Keychains/System.keychain
sudo /usr/bin/security delete-certificate -c "AC-SRVSVCNAM-DQI" /Library/Keychains/System.keychain
sudo /usr/bin/security delete-certificate -c "AC-SRVSVCNAM-257-DQI" /Library/Keychains/System.keychain
sudo /usr/bin/security delete-certificate -c "AC-SRVSVCNAM-256" /Library/Keychains/System.keychain

# Suppression receipts
sudo rm -rf "/Library/Receipts/SrvSVcnam_*"
sudo rm -rf "/var/db/receipts/org.cnamts.SrvSVcnam_*"
sudo pkgutil --forget org.cnamts.SrvSVcnam_Install.pkg
sudo pkgutil --forget org.cnamts.SrvSVcnam


#suppression des fichiers adm des repertoires de suivi de parc
#définition des répertoires
CheminFSV="/Library/Preferences/santesocial/fsv"
CheminFSV2="/Library/Application Support/santesocial/fsv"
CheminSesam="/Library/Preferences/sesam.ini"
CheminSesam2="/tmp/sesam2.ini"
CheminDirectories="/tmp/directories.txt"

# Fonction de suppression du fichier adm dans les répertoires désignés par les fichiers sesam.ini
ProcessSubFolders()
{
find "$1" -type f -name sesam.ini> "${CheminDirectories}"

while IFS= read -r line
do
sudo cp "${line}" "${CheminSesam2}"
Destination=$(GetRepertoireTravail `echo ${CheminSesam2}`)
# On supprime les caractères de fin de chaine
Destination=$(echo $Destination | tr -d '\r')
#echo "${Destination}"
sudo chown -R root:admin "${Destination}"
sudo chmod 777 "${Destination}"
if [ -d "${Destination}" ]
then
# On vérifie la présence du fichier adm
if [ -f "${Destination}/150.adm" ]
then
sudo rm -f "${Destination}/150.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/157.adm" ]
then
sudo rm -f "${Destination}/157.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/158.adm" ]
then
sudo rm -f "${Destination}/158.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/159.adm" ]
then
sudo rm -f "${Destination}/159.adm"
fi
fi
done < "${CheminDirectories}"
}

# Fonction de lecture du chemin du repertoire de travail dans le fichier sesam.ini passe en parametre
GetRepertoireTravail()
{
# lecture du paramètre d'entrée de la fonction
local file="$1"
while IFS= read -r line
do
if [ `echo $line | grep -c "RepertoireTravail"` -gt 0 ]
then
# la ligne du sesam.ini est bien la cle RepertoireTravail
# Extraction de la valeur de la cle RepertoireTravail
echo "${line:18}"
fi
done <"$file"
}

## Suppression du fichier adm pour les FSV non isolées
if [ -f "${CheminSesam}" ]
then
Destination=$(GetRepertoireTravail "${CheminSesam}")
# On supprime les caractères de fin de chaine
Destination=$(echo $Destination | tr -d '\r')
#echo "${Destination}"
sudo chown -R root:admin "${Destination}"
sudo chmod 777 "${Destination}"
# On vérifie la présence du fichier adm
if [ -f "${Destination}/150.adm" ]
then
sudo rm -f "${Destination}/150.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/157.adm" ]
then
sudo rm -f "${Destination}/157.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/158.adm" ]
then
sudo rm -f "${Destination}/158.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/159.adm" ]
then
sudo rm -f "${Destination}/159.adm"
fi
fi

# Appel de la fonction de suppression du fichier adm pour les FSV isolés
if [ -d "${CheminFSV}" ]
then
ProcessSubFolders "${CheminFSV}"
ProcessSubFolders "${CheminFSV2}"
fi

# Suppression du fichier temporaire
if [ -f "${CheminDirectories}" ]
then
rm -f "${CheminDirectories}"
fi
if [ -f "${CheminSesam2}" ]
then
rm -f "${CheminSesam2}"
fi

#suppression des fichiers adm des repertoires commun
rm -f "/Library/Application Support/santesocial/commun/adm/150.adm"
rm -f "/Library/Application Support/santesocial/commun/adm/produits/158.adm"


osarch=$(uname -m)

#TRAITEMENTS PROPRES A CHAQUE UTILISATEUR
#----------------------------------------

if [ "${osarch}" = "arm64" ]; then
    "/Library/Application Support/santesocial/Firefox/jq" '.policies.Certificates.Install |= . - ["/Library/Application Support/santesocial/SrvSVcnam/AC-SRVSVCNAM.pem"]' "/Applications/Firefox.app/Contents/Resources/distribution/policies.json" > "/Applications/Firefox.app/Contents/Resources/distribution/policies.json.tmp"
    rm "/Applications/Firefox.app/Contents/Resources/distribution/policies.json"
    mv "/Applications/Firefox.app/Contents/Resources/distribution/policies.json.tmp" "/Applications/Firefox.app/Contents/Resources/distribution/policies.json"
else
#debut boucle sur tous les utilisateurs
#--------------------------------------

for user in `ls /Users|grep -v Shared|grep -v localized`
do

user_home=/Users/$user

rm "$user_home/Library/Application Support/Google/Chrome/NativeMessagingHosts/fr.sesamvitale.srvsvcnam_native_messaging_host.json"
rm "$user_home/Library/Application Support/Mozilla/NativeMessagingHosts/fr.sesamvitale.srvsvcnam_native_messaging_host.json"

# Suppression des certificats dans le magasin Firefox
cheminCourant="/Library/Application Support/santesocial/Firefox"
cheminProfiles="$user_home/Library/Application Support/Firefox/Profiles"

cd "${cheminCourant}"

find "$user_home"'/Library/Application Support/Firefox/Profiles' -name cert9.db  -o -name cert8.db > /tmp/find.out

while read p; do
delete_certificates "$p"
done </tmp/find.out

#fin boucle sur tous les utilisateurs
done
fi

sudo rm -rf "/Library/Application Support/santesocial/Firefox"

for user in `ls /Users|grep -v Shared|grep -v localized`
do

user_home=/Users/$user

## Suppression des fichiers du bureau 
for file in SrvSVcnam_Lanceur SrvSVcnam_Lanceur.app Webmedecin.url AmeliPro.url amelipro.url amelipro EspacePro.url WebDMP.url EspacePro WebDMP AmeliPro         
do
    rm -rf $user_home/Desktop/$file
done

#fin boucle sur tous les utilisateurs
done

exit 0

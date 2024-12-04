#!/bin/sh

santesocial_root="/Library/Application Support/santesocial/"

webapp_env_suffix=prod

webapp_version=2.02.04

webapp_short_name="amelipro connect"
webapp_short_name2="amelipro"
xcode_target_name="Navigateur $webapp_short_name2"

webapp_identifier=fr.sesam-vitale.navigateur-amelipro

webapp_prefix=$webapp_short_name

webapp_prefix_version="amelipro_connect"-"$webapp_version"

webapp_env_suffix_blank=""

if [[ "$webapp_env_suffix" != "prod" ]]
then
webapp_prefix_version="amelipro_connect"-"$webapp_version"-"$webapp_env_suffix"
xcode_target_name+=" $webapp_env_suffix"
fi

webapp_name="$webapp_short_name"

webapp_no_app_name="$webapp_name"

webapp_app_name="$webapp_name".app

webappProjFolder="../amelipro_connect/proj"
webapp_proj_path="$webappProjFolder/navigateur_amelipro.xcodeproj"
webapp_entitlements_path="$webappProjFolder/../src/Ressources/navigateur_amelipro.entitlements"

#webappBaseBuildFolder="../../NavigateurSanteSocial/macOS/trunk/proj/binaries/$webapp_env_suffix/"
webappBaseBuildFolder="$webappProjFolder/binaries/$webapp_env_suffix"
webapp_release_build_path="$webappBaseBuildFolder/Release/$webapp_app_name"
webapp_debug_build_path="$webappBaseBuildFolder/Debug/$webapp_app_name"

webapp_app_dir=/Applications

webapp_log_dir=/Library/Logs/santesocial/"$webapp_short_name2"/

webapp_app_path="$webapp_app_dir"/"$webapp_app_name"

webapp_conf_dir="$santesocial_root"/"$webapp_short_name2"/
webapp_licences_dir="$santesocial_root"/"$webapp_short_name2"/licences/

make_alias_script=make_alias.sh

make_alias_path="$webapp_conf_dir"/"$make_alias_script"

CheminFSV="/Library/Preferences/santesocial/fsv"
CheminFSV2="$santesocial_root"/fsv
webapp_adm_file=192.adm
CheminAdm="$webapp_conf_dir"/"$webapp_adm_file"
CheminSesam="/Library/Preferences/sesam.ini"
commun_adm_folder="/Library/Application Support/santesocial/commun/adm/produits"


codesign_signature_application='Developer ID Application: GIE SESAM-Vitale (5H8W5749XS)'
codesign_signature_installer='Developer ID Installer: GIE SESAM-Vitale (5H8W5749XS)'

notarization_primary_bundle_id=ameliproConnect
#!/bin/sh

sudo rm -f /tmp/webapp_uninstall_log_file.txt
exec > /tmp/webapp_uninstall_log_file.txt 2>&1


# arret de l'application

for X in `ps acx | grep -i "$webapp_short_name" | awk {'print $1'}`;
do
sudo kill $X;
done



sudo rm -rf "$webapp_log_dir"

echo suppression : "$webapp_app_dir"/"$webapp_no_app_name"*

sudo rm -rf "$webapp_app_dir"/"$webapp_no_app_name"*

sudo rm -f "$webapp_conf_dir/com.user.create.amelipro.shortcut.on.login.plist"
sudo rm -f "$webapp_conf_dir/log4crc.xml"
sudo rm -rf "$webapp_conf_dir/licences/"
sudo rm -f "$webapp_conf_dir/make_alias.sh"
sudo rm -f "$webapp_conf_dir/uninstall.sh"


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
if [ -f "${Destination}/$webapp_adm_file" ]
then
sudo rm -f "${Destination}/$webapp_adm_file"
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
if [ -f "${Destination}/$webapp_adm_file" ]
then
sudo rm -f "${Destination}/$webapp_adm_file"
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
rm -f "/Library/Application Support/santesocial/commun/adm/produits/$webapp_adm_file"


# Suppression du .DS_Store sinon le test du répertoire vide qui suit ne fonctionne pas
sudo rm -rf "$webapp_app_dir/.DS_Store" 

# s'il n'y a pas de fichier .conf, on supprime complétement le répertoire
if [ -z '$(ls -A $"webapp_app_dir"' ]; then
   	echo "Empty"
	sudo rm -rf "$webapp_conf_dir"   
else
   echo "Not Empty"
fi



#suppression fichier contexte sparkle
#------------------------------------

rm  -f ~/Library/Preferences/"$webapp_identifier".plist

sudo pkgutil --forget "$webapp_identifier"

sudo rm -f ~/Library/LaunchAgents/com.user.create.amelipro.shortcut.on.login.plist 

#boucle sur les utilisateurs
#---------------------------

for user in `dscl . list /Users | grep -v '_' |grep -v root | grep -v nobody | grep -v daemon`
do
	su - $user -c "rm -f ~/Desktop/\"$webapp_name\""
done

exit 0
#
##killall Dock
#
#
#

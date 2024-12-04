#!/bin/sh

santesocial_root="/Library/Application Support/santesocial/"

webapp_version=2.01.19

webapp_short_name=DiagAM

webapp_conf_dir=diagAM

webapp_identifier=fr.sesamvitale.diagAM

webapp_pkg_identifier="$webapp_identifier".pkg

webapp_env_suffix=

webapp_project_name=diagam

webapp_prefix="$webapp_short_name"

webapp_prefix_version="$webapp_prefix"-"$webapp_version"

if [[ "$webapp_env_suffix" != "" ]]
then
webapp_prefix_version+="-""$webapp_env_suffix"
fi


webapp_module_name=$webapp_project_name

if [[ "$webapp_env_suffix" != "" ]]
then
webapp_module_name+="_$webapp_env_suffix"
fi




webapp_name="$webapp_short_name"

webapp_app_name="$webapp_name".app

if [[ "$webapp_env_suffix" != "" ]]
then
dev_dir="$webapp_short_name"_"$webapp_env_suffix"
else
dev_dir="$webapp_short_name"
fi

webapp_release_build_path=../projet/"$webapp_project_name"/build/Release/"$webapp_module_name"
webapp_debug_build_path=../projet/"$webapp_project_name"/build/Debug/"$webapp_module_name"


webapp_app_dir=/Applications

webapp_log_dir=/Library/Logs/santesocial/"$webapp_short_name"/

webapp_app_path="$webapp_app_dir"/"$webapp_app_name"

webapp_conf_dir="$santesocial_root"/"$webapp_conf_dir"/

CheminFSV="/Library/Preferences/santesocial/fsv"
CheminFSV2="$santesocial_root"/fsv
webapp_adm_file=166.adm
CheminAdm="$webapp_conf_dir"/"$webapp_adm_file"
CheminSesam="/Library/Preferences/sesam.ini"
commun_adm_folder="/Library/Application Support/santesocial/commun/adm/produits"




#!/bin/sh

sudo rm -f /tmp/diagam_uninstall_log_file.txt
exec > /tmp/diagam_uninstall_log_file.txt 2>&1

#suppressions du repertoire de l'appli +  securite sur les rm

if [[ "$webapp_app_path" = *.app ]]
then
sudo rm -rf "$webapp_app_path"
fi

if [[ "$webapp_short_name" != "" ]]
then
sudo rm -rf "$webapp_conf_dir"
fi

if [[ "$webapp_short_name" != "" ]]
then
sudo rm -rf "$webapp_log_dir"
fi

#suppression fichier contexte sparkle
#------------------------------------
sudo rm  -f ~/Library/Preferences/"$webapp_identifier".plist

sudo pkgutil --forget "$webapp_pkg_identifier"


#les premieres versions de diagAM 2.0 macOs ont créé des fichiers 166.adm à tort
#ce nom est déjà utilisé pour le suivi de parc d'un autre livrable GIE
#le nouveau adm pour diagam 2.0 macOS est 165.adm (comme pour windows)
#le présent script de désinstallation ne va supprimer que les 166.adm contenant la chaine 'DIAGAM'
#on préserve ainsi les 166.adm légitimes (ceux de l'autre livrable GIE) mais aussi, c'est un moindre mal, les 166.adm sans contenu 'DIAGAM' déposés à tort par les versions précédentes de DiagAM 2.0
#Par ailleur, le script va supprimer tous les 165.adm (avec ou sans la chaine 'DIAGAM')


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
if [ -f "${Destination}/165.adm" ]  
then
sudo rm -f "${Destination}/165.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/166.adm" ] && grep "DIAGAM" "${Destination}/166.adm" 
then
sudo rm -f "${Destination}/166.adm"
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
if [ -f "${Destination}/165.adm" ]  
then
sudo rm -f "${Destination}/165.adm"
fi

# On vérifie la présence du fichier adm
if [ -f "${Destination}/166.adm" ] && grep "DIAGAM" "${Destination}/166.adm" 
then
sudo rm -f "${Destination}/166.adm"
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
if [ -f "/Library/Application Support/santesocial/commun/adm/produits/165.adm" ] 
then
sudo rm -f "/Library/Application Support/santesocial/commun/adm/produits/165.adm"
fi
if [ -f "/Library/Application Support/santesocial/commun/adm/produits/166.adm" ] && grep -q "DIAGAM" "/Library/Application Support/santesocial/commun/adm/produits/166.adm"
then
sudo rm -f "/Library/Application Support/santesocial/commun/adm/produits/166.adm"
fi


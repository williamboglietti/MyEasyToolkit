#!/bin/bash
#--------------------------------------------------------------------
# Auteur : MyEasyOptic
# Date   : voir ci-dessous
#--------------------------------------------------------------------
# Desinstalleur de la Cryptolib CPS pour MacOS
# 
# Supprime automatiquement tous les composants des Cryptolib 
# CPS2ter et CPS3 fourni par l'ASIP Sante.
#--------------------------------------------------------------------

VERSION_SCRIPT="version du 23 octobre 2024"

# Declaration des couleurs
VERT="\\033[1;32m"
NORMAL="\\033[0;39m"
ROUGE="\\033[1;31m"
ROSE="\\033[1;35m"
BLEU="\\033[1;34m"
BLANC="\\033[0;02m"
BLANCLAIR="\\033[1;08m"
JAUNE="\\033[1;33m"
CYAN="\\033[1;36m"
BOLD="\\033[1m"

# Declaration des fonctions
#--------------------------------------------------------------------
show_help ()
{
	echo ""
	echo -e "$BOLD""  "$0"""$NORMAL"" (""$VERSION_SCRIPT"")"
 	echo ""
	echo "        "$0" [-h] | [-m] | [[-v] [-g|G] [-L]] |"
    echo "             [[-t|-T] [-p|-P] [-r|-R]"
    echo "             [--startupdelay-tokend change|usine|VALEUR]"
	echo "             [--logs-asip] [--logs-giesv] [--logs-all]"
	echo "             [—-caches-asip]"
    echo "             [--traces-asip false|true] [--traces-giesv error|debug]"
	echo "             [--infos-sys]"
    echo "             [--debug spindump|sysdiagnose]"
    echo "             [--zip]]"
 	echo ""
	echo "  Desinstalleur de la Cryptolib CPS pour MacOS X 10.4 et superieurs :"
 	echo ""
	echo "  Ce script supprime automatiquement tous les composants des Cryptolibs"
	echo "  CPS v4 (CPS2ter) et v5 (CPS3) fournies par l'ASIP Sante. Il traite les"
	echo "  Cryptolibs CPS v4 en filiere GALSS et Full PCSC."
    echo ""
	echo "  Ce script permet de des/activer le tokend et/ou le lien PSS vers PC/SC."
    echo ""
	echo "  Ce script permet de configurer divers parametres des composants de "
    echo "  l'ASIP Sante et du GIE SESAM Vitale."
	echo ""
	echo -e "$BOLD""      -h""$NORMAL""  affiche l'aide"
	echo ""
	echo -e "$BOLD""      -v""$NORMAL""  affiche des messages supplementaires"
	echo ""
	echo -e "$BOLD""      -g""$NORMAL""  supprime aussi les composants GALSS et "
	echo "          API de lecture Vitale du GIE-SV."
	echo "          Cette option conserve la configuration"
	echo "          lecteur (fichiers galss.ini et io_comm.ini)."
	echo ""
	echo -e "$BOLD""      -G""$NORMAL""  supprime aussi les composants GALSS et "
	echo "          API de lecture Vitale du GIE-SV."
	echo "          Cette option supprime aussi la configuration"
	echo "          lecteur (fichiers galss.ini et io_comm.ini)."	
	echo ""
	echo -e "$BOLD""      -L""$NORMAL""  supprime aussi les composants API de "
	echo "          lecture Vitale du GIE-SV."
	echo ""
	echo -e "$BOLD""      --menu,-m""$NORMAL""  affiche un menu d’assistance "
	echo ""
	echo -e "$BOLD""      -t""$NORMAL""  desactive le TokenD de la Cryptolib CPS "
	echo ""
	echo -e "$BOLD""      -T""$NORMAL""  active le TokenD de la Cryptolib CPS "
	echo ""
	echo -e "$BOLD""      -p""$NORMAL""  desactive le chargement automatique de pcscd "
	echo "          (A utiliser quand un lecteur PC/SC est branche)"
	echo ""
	echo -e "$BOLD""      -P""$NORMAL""  active le chargement automatique de pcscd "
	echo "          sur lecteur PSS"
	echo "          (A ne pas utiliser quand un lecteur PC/SC est branche)"
	echo ""
	echo -e "$BOLD""      -r""$NORMAL""  desactive le lien PSS vers PC/SC"
    echo "          (reader.conf sous Mac OS inferieur a 10.9 ou GALSSDriver.bundle sous Mac OS superieur a 10.10)"
	echo ""
	echo -e "$BOLD""      -R""$NORMAL""  active le lien PSS vers PC/SC (reader.conf ou GALSSDriver.bundle)"
	echo ""
    echo -e "$BOLD""      --startupdelay-tokend change|usine|VALEUR""$NORMAL""  configure le delai de chargement "
    echo -e "          du TokenD apres le demarrage du poste de travail :"
    echo -e "            - ""$BOLD""change""$NORMAL"" : le script demande la valeur a l'operateur."
    echo -e "            - ""$BOLD""usine""$NORMAL"" : le script remet la valeur d'usine."
    echo -e "            - ""$BOLD""VALEUR""$NORMAL"" : le script configure le parametre ""$BOLD""ifdStartupDelay""$NORMAL"" a VALEUR."
	echo ""
    echo -e "$BOLD""      --logs-asip""$NORMAL""  supprime les logs de la Cryptolib CPS"
	echo ""
	echo -e "$BOLD""      --logs-giesv""$NORMAL""  supprime les logs du GALSS"
	echo ""
	echo -e "$BOLD""      --logs-all""$NORMAL""  supprime tous les logs"
	echo ""
	echo -e "$BOLD""      --caches-asip""$NORMAL""  supprime les caches des CPS"
	echo ""
	echo -e "$BOLD""      --traces-asip false|true""$NORMAL""  Desactive, i.e. ""$BOLD""false""$NORMAL"", ou active, i.e. ""$BOLD""true""$NORMAL"", "
	echo "          les traces de la Cryptolib CPS"
    echo ""
	echo -e "$BOLD""      --traces-giesv error|debug""$NORMAL""  Desactive, i.e. ""$BOLD""error""$NORMAL"", ou active, i.e. ""$BOLD""debug""$NORMAL"", "
	echo "          les traces du GALSS"
	echo ""
	echo -e "$BOLD""      --debug spindump|sysdiagnose""$NORMAL""  lance la commande de debug correspondante"
	echo ""
	echo -e "$BOLD""      --infos-sys""$NORMAL""  affiche des informations systemes et les archives dans les logs"
	echo ""
    echo -e "$BOLD""      --zip""$NORMAL""  archive dans le repertoire courant les logs/spindump/sysdiagnose"
	echo ""
	echo " Remarques :"
	echo "    - ce script necessite le mot de passe administrateur."
	echo "    - le repertoire tools et son contenu sont indispensables au "
	echo "      fonctionnement de ce script pour certaines commandes."
	echo "    - les options 'vgGL' ne peuvent pas etre traitees simultanemment "
	echo "      avec d autres options."
	echo ""
	echo " Exemples :"
    echo "    - Lancer le menu d'assistance :"
    echo -e "$BOLD""         uninstall.sh --menu""$NORMAL"
    echo "    - Modifier le delai de demarrage du TokenD sur une insertion de carte CPS :"
    echo -e "$BOLD""         uninstall.sh --startupdelay-tokend change""$NORMAL"
    echo "    - Activer les traces de la Cryptolib CPS et du GALSS :"
	echo -e "$BOLD""         uninstall.sh --traces-asip true --traces-giesv debug""$NORMAL"
    echo "    - Desactiver les traces de la Cryptolib CPS et du GALSS :"
	echo -e "$BOLD""         uninstall.sh --traces-asip false --traces-giesv error""$NORMAL"
	echo "    - Archiver les logs existants et les informations systemes :"
	echo -e "$BOLD""         uninstall.sh --infos-sys --zip""$NORMAL"
	echo "    - Pour prendre des traces lors d un essai sur un poste, supprimer les logs anciens, lancer"
	echo "      un spindump et archiver les logs et les informations systemes en fin d'essai :"
	echo -e "$BOLD""         uninstall.sh --traces-asip true --traces-giesv debug --logs-all --infos-sys --debug spindump --zip""$NORMAL"
    echo ""
}

show_menu ()
{
	echo ""
	echo -e "$BOLD""ASSISTANT DE MODIFICATION POST-INSTALLATION DES COMPOSANTS DE L'ASIP SANTE""$NORMAL"
	echo ""
	echo "Cet assistant vous guide dans la modification de l'installation de nos composants suivant les specificites"
	echo "de la configuration du poste de travail."
	echo ""
	echo "Vous pouvez selectionner un cas parmi ceux decrits ci-dessous :"
	echo ""
	echo -e "$BOLD"" 1""$NORMAL"") Desactiver l'emulation PC/SC pour lecteur PSS."
	echo -e "    - Ce choix intervient lorsque l'utilisateur possede une ""$BOLD""configuration mixte integrant des lecteurs PSS et PC/SC""$NORMAL""."
	echo -e "    - L'action systeme correspond a un renommage du fichier reader.conf ou GALSSDriver.bundle suivant la version de Mac OS X."
	echo -e "    - Avec ce choix, les lecteurs PC/SC peuvent etre utilises avec Safari, mais pas les lecteurs PSS."
	echo -e ""
    echo -e "$BOLD"" 2""$NORMAL"") Desactiver totalement l'interface systeme vers les lecteurs de carte a puce."
	echo -e "    - Ce choix intervient lorsque l'utilisateur possede une ""$BOLD""configuration integrant uniquement des lecteurs PSS""$NORMAL""."
	echo -e "    - L'action systeme correspond a un renommage des fichiers tokend et reader.conf ou GALSSDriver.bundle suivant la version de Mac OS X."
	echo -e "    - Avec ce choix, plus aucun lecteur ne pourra etre utilise avec Safari."
	echo -e ""
    echo -e "$BOLD"" 3""$NORMAL"") Revenir a l'etat initial de l'installation."
	echo -e "    - Ce choix permet d'""$BOLD""annuler une precedente modification d'installation""$NORMAL""."
	echo -e "    - L'action systeme consiste a un nommage correct des fichiers tokend, reader.conf ou GALSSDriver.bundle suivant la version de Mac OS X."
	echo -e "    - Avec ce choix, les lecteurs PSS et PC/SC peuvent etre utilises avec Safari."
    echo -e ""
    echo -e "$BOLD"" 4""$NORMAL"") Regler le ""$BOLD""delai de chargement du TokenD""$NORMAL"" apres le demarrage du poste de travail."
    echo ""
    echo -e "$BOLD"" q""$NORMAL"") Quitter"
	echo ""
	echo -n -e "Votre choix (""$BOLD""1, 2, 3""$NORMAL"" ou ""$BOLD""4""$NORMAL"") : "
    read -n 1 reponse
    echo ""
    clear
	case $reponse in
		1 ) READERCFG_ACTIVE=0
		READERCFG=1

		PCSCDAUTO_ACTIVE=0
		PCSCDAUTO=1

		ACTIVATION=1
		;;
		2 ) READERCFG_ACTIVE=0
		READERCFG=1

		PCSCDAUTO_ACTIVE=0
		PCSCDAUTO=1

		TOKEND_ACTIVE=0
		TOKEND=1

		ACTIVATION=1
		;;
		3 ) READERCFG_ACTIVE=1
		READERCFG=1

		PCSCDAUTO_ACTIVE=1
		PCSCDAUTO=1

		TOKEND_ACTIVE=1
		TOKEND=1
        
        CONF_CPS3=1
        STARTUPDELAY=usine
        
		ACTIVATION=1
		;;
        4) CONF_CPS3=1
        STARTUPDELAY=change
        ACTIVATION=1
        ;;
		* ) exit 0
		;;
	esac

}

GetProcID ()
{
    local pid=$(ps -A | grep "$1" | grep -v grep | awk '{print $1}')

    echo $pid
    if [ -z "${pid}" ]; then
        return 0
    else
        return 1
    fi
}

StopProcess ()
{
    local pidproc=$(GetProcID $1)

    if [ "$pidproc" = "" ]; then
        DisplayTrace "Processus $1 non trouve."

        return 1
    fi

    DisplayTrace "Terminaison du processus $1 (pid=${pidproc})"

    sudo kill -TERM $pidproc

    for i in {1..30}
    do 
        sleep 1

        pidproc=$(GetProcID $1)
        
        if [ "$pidproc" = "" ]; then
            echo "OK"
            return 1
        fi
        echo -n .
    done

    sudo kill -KILL $pidproc >>/dev/null 2>&1
    echo "OK"
    return 1
}

Control_c()
{
    echo ""
    echo -e "$VERT""Interrompu par l'utilisateur...""$NORMAL"
    echo ""
    exit 1
}

DisplayTrace ()
{
    if [ $verbose -eq "1" ]
    then
		echo -e "$ROUGE""$1""$NORMAL"
	fi
}

DisplayStep ()
{
    STEP=`expr $STEP + 1`
    echo ""
    echo -e "$BLEU""Etape ${STEP} : ""$NORMAL""$1"
}

CleanADMs ()
{
	for i in $ADM_LIST
	do
		if [ -f "$1/$i" ]; then
			DisplayTrace "Suppression du fichier : $1/$i"
			rm -f "$1/$i"
		fi
	done
}


ProcessCleanADMs ()
{
	# remplacer l'espace par un plus puis les CRs par un espace
	# pour que le 'for' qui suit ne s'emmele pas les pinceaux
	ADM_CONF_DIRS=`ls -d /Library/Application\ Support/fsv/*/conf | tr ' ' '+' | tr '\n' ' '`
	
	ADM_CONF_DIRS=`echo $ADM_CONF_DIRS /Library/Preferences`
	
	for CUR_DIR in $ADM_CONF_DIRS
	do
		# remettre le caractere espace
		CUR_DIR=`echo $CUR_DIR | tr '+' ' '`
		
		CONFIG_FILE="$CUR_DIR/SESAM.INI"

		# traiter chaque repertoire afin de trouver le fichier SESAM.INI
		if [ -f "$CONFIG_FILE" ]
		then

			# lire le fichier SESAM.INI ligne par ligne
			while read LINE
			do
				# ignorer les commentaires
				COMMENT_LINE=`echo "$LINE" | grep "^;" | wc -l | awk '{sub(/^ */,"",$0)}1'`
				if [ "$COMMENT_LINE" = "1" ]; then
					continue
				fi

				# verifier que nous sommes bien dans la section [COMMUN] 
				if [[ "$LINE" == "[COMMUN]"* ]]; then
					IS_COMMUN_SECTION=true
				elif [[ "$LINE" == "["* ]]
				then
					IS_COMMUN_SECTION=false
				fi

				# ne pas traiter la ligne si elle n est pas dans la section [COMMUN]
				if [ "$IS_COMMUN_SECTION" = "false" ]; then
					continue
				fi

				# extraire la cle et sa valeur
				KEY=`echo $LINE | awk 'BEGIN { FS = "=" }; {print $1}'`
				WORKING_DIR=`echo $LINE | awk 'BEGIN { FS = "=" }; {print $2}'`

				# Faire en sorte de ne pas avoir de CR en fin de ligne (DOS format)
				WORKING_DIR=${WORKING_DIR//$'\r'/}

				# recuperer le repertoire de travail
				if [ "$KEY" = "RepertoireTravail" ]
				then
					# suppression des fichiers adm dans le repertoire specifie
					CleanADMs "$WORKING_DIR"
				fi
			done < "$CONFIG_FILE" 

		fi
	
	done
	
	# Pour finir, suppression des adms du repertoire commun
	CUR_DIR="/Library/Application Support/santesocial/commun/adm"
	if [ -d "$CUR_DIR" ]; then
		CleanADMs "$CUR_DIR"
	fi
	
}

# Declaration des variables globales
#--------------------------------------------------------------------
STEP=0
OPTIND=1
verbose=0

ALL=0

GIESV=0
GALSS=0
CONFLECTEUR=0
APILEC=0

ACTIVATION=0

TOKEND=0
TOKEND_ACTIVE=1

PCSCDAUTO=0
PCSCDAUTO_ACTIVE=1

READERCFG=0
READERCFG_ACTIVE=1

LOG_ASIP_DEL=0
LOG_GIE_DEL=0

CACHE_CPS_DEL=0

CONF_CPS3=0
SIGN_HASH=true
CONF_TRACES=0
TRACES_ACTIVE=
CACHES_PATH=
STARTUPDELAY=

CONF_GALSS=0
TRACES_GALSS_ACTIVE=error

DEBUG_SPINDUMP=0
DEBUG_SYSDIAGNOSE=0

DEBUG_INFOSYS=0

ZIP_INFOS=0

USERPROFILE=""

ADM_154="154.adm"
ADM_155="155.adm"
ADM_157="157.adm"
ADM_174="174.adm"
ADM_170="170.adm"

ADM_LIST=""
ADM_LIST="$ADM_LIST $ADM_154"
ADM_LIST="$ADM_LIST $ADM_155"
ADM_LIST="$ADM_LIST $ADM_157"
ADM_LIST="$ADM_LIST $ADM_174"
ADM_LIST="$ADM_LIST $ADM_170"

clear

# Traitement des options de ligne de commande
#--------------------------------------------------------------------
while [[ $# > 0 ]]
do
	opt="$1"
	shift

	case $opt in
		-v) verbose=1
			;;
		-a) ALL=1
			GIESV=1
			GALSS=1
			CONFLECTEUR=1
			APILEC=1
			;;
		-G) GIESV=1
			GALSS=1
			CONFLECTEUR=1
			APILEC=1
			;;
		-g) GIESV=1
			GALSS=1
			APILEC=1
			;;
		-L) GIESV=1
			APILEC=1
			;;
		-t) TOKEND_ACTIVE=0
			TOKEND=1
			ACTIVATION=1
			;;
		-T) TOKEND_ACTIVE=1
			TOKEND=1
			ACTIVATION=1
			;;
		-p) PCSCDAUTO_ACTIVE=0
			PCSCDAUTO=1
			ACTIVATION=1
			;;
		-P) PCSCDAUTO_ACTIVE=1
			PCSCDAUTO=1
			ACTIVATION=1
			;;
		-r) READERCFG_ACTIVE=0
			READERCFG=1
			ACTIVATION=1
			;;
		-R) READERCFG_ACTIVE=1
			READERCFG=1
			ACTIVATION=1
			;;
        --startupdelay-tokend) CONF_CPS3=1
            STARTUPDELAY=$1
            shift
            ACTIVATION=1
            ;;
		--logs-asip) LOG_ASIP_DEL=1
			ACTIVATION=1
			;;
		--logs-giesv) LOG_GIE_DEL=1
			ACTIVATION=1
			;;
		--logs-all) LOG_ASIP_DEL=1
			LOG_GIE_DEL=1
			ACTIVATION=1
			;;
		--caches-asip) CACHE_CPS_DEL=1
			ACTIVATION=1
			;;
		--traces-asip) CONF_CPS3=1
			TRACES_ACTIVE=$1
			shift
			ACTIVATION=1
			;;
        --traces-giesv) CONF_GALSS=1
            TRACES_GALSS_ACTIVE=$1
            shift
            ACTIVATION=1
            ;;
        --infos-sys)
            DEBUG_INFOSYS=1
            ACTIVATION=1
            ;;
		--debug) case $1 in
				spindump) DEBUG_SPINDUMP=1
					shift
					;;
				sysdiagnose) DEBUG_SYSDIAGNOSE=1
					shift
					;;
			esac
			ACTIVATION=1
			;;
		--zip) ZIP_INFOS=1
			ACTIVATION=1
			;;
		--menu | -m) show_menu
			;;
		-h | *) show_help
			exit 0
			;;
	esac
done

#-----------------------------------------------------------------------------------------
# Avertissement
echo ""
echo -e "$ROUGE""-------------------------------------------------------------------""$NORMAL"
echo -e "$ROUGE""                            AVERTISSEMENT !                        ""$NORMAL"
echo -e "$ROUGE""-------------------------------------------------------------------""$NORMAL"
echo -e "$ROUGE""Cet outil est uniquement a destination des personnes habilitees par""$NORMAL"
echo -e "$ROUGE""les supports techniques de MyEasyOptic.""$NORMAL"
echo ""
echo -e "$ROUGE""Il realise des operations critiques sur le poste de travail.""$NORMAL"
echo -e "$ROUGE""-------------------------------------------------------------------""$NORMAL"
echo ""
echo "(""$VERSION_SCRIPT"")"
echo ""
#-----------------------------------------------------------------------------------------
# Demande de confirmation
if [ $ACTIVATION -eq "0" ]
then
	echo -e "$BLEU""Ce programme fourni par MyEasyOptic va desinstaller les composants et certificats de la Cryptolib CPS.""$NORMAL"
	if [ $GIESV -eq "1" ]
	then
		echo ""
		echo "Il supprimera aussi les composants suivants du GIE-SV :"
		if [ $GALSS -eq "1" ]
		then
			echo -n "  - GALSS"
			if [ $CONFLECTEUR -eq "1" ]
			then
				echo " et sa configuration lecteur."
			else
				echo "."
			fi
		fi
		if [ $APILEC -eq "1" ]
		then
			echo "  - API de lecture Vitale (Installation par le DMP)."
		fi
	fi
else
	echo -e "$BLEU""Ce programme fourni par l'ASIP Sante va :""$NORMAL"
	if [ $TOKEND -eq "1" ]
	then
		echo -n "  - "
		if [ $TOKEND_ACTIVE -eq "0" ]
		then
			echo -n "des"
		fi
		echo "activer le Tockend de la cryptolib CPS."
	fi
	if [ $PCSCDAUTO -eq "1" ]
	then
		echo -n "  - "
		if [ $PCSCDAUTO_ACTIVE -eq "0" ]
		then
			echo -n "des"
		fi
		echo "activer le chargement automatique de pcscd au demarrage."
	fi
	if [ $READERCFG -eq "1" ]
	then
		echo -n "  - "
		if [ $READERCFG_ACTIVE -eq "0" ]
		then
			echo -n "des"
		fi
		echo "activer le lien PSS vers PC/SC (reader.conf)."
	fi
	if [ $LOG_ASIP_DEL -eq "1" ]
	then
		echo -n "  - "
		echo "supprimer les logs de la Cryptolib CPS."
	fi
	if [ $LOG_GIE_DEL -eq "1" ]
	then
		echo -n "  - "
		echo "supprimer les logs du GALSS."
	fi
	if [ $CACHE_CPS_DEL -eq "1" ]
	then
		echo -n "  - "
		echo "supprimer les caches de CPS."
	fi
	if [ $CONF_CPS3 -eq "1" ]
	then
		echo -n "  - "
		echo "configurer la Cryptolib CPS."
	fi
	if [ $CONF_GALSS -eq "1" ]
	then
		echo -n "  - "
		echo "configurer le GALSS."
	fi
	if [ $DEBUG_SPINDUMP -eq "1" ]
	then
		echo -n "  - "
		echo -e "lancer la commande ""$BOLD""spindump -notarget 120 10 -file /Library/Logs/santesocial/CPS/spindump_DATETIME.txt""$NORMAL"" ."
	fi
	if [ $DEBUG_SYSDIAGNOSE -eq "1" ]
	then
		echo -n "  - "
		echo -e "lancer la commande ""$BOLD""sysdiagnose -f /Library/Logs/santesocial/CPS/""$NORMAL"" ."
	fi
    if [ $DEBUG_INFOSYS -eq "1" ]
	then
        echo -n "  - "
		echo -e "afficher les informations systemes (cette option necessite une attente de votre part)."
    fi
	if [ $ZIP_INFOS -eq "1" ]
	then
		echo -n "  - "
		echo -e "archiver les logs/spindump/sysdiagnose"
	fi
fi

echo ""
echo -n -e "Voulez-vous continuer (""$ROUGE""O""$NORMAL"")ui/(""$ROUGE""N""$NORMAL"")on ? " 
read -n 1 reponse 

case $reponse in
    o | O | Oui | OUI ) ;;
    * ) exit 0;;
esac

trap Control_c SIGINT

declare -ir FALSE=1
declare -ir TRUE=0
#-----------------------------------------------------------------------------------------
# Debut des traitements
#-----------------------------------------------------------------------------------------

# Cas de la desinstallation des Cryptolibs
#-----------------------------------------------------------------------------------------
if [ $ACTIVATION -eq "0" ]
then
    TOOLPATH=$0
    TOOLPATH=`dirname "${TOOLPATH}"`
    
    #   #-----------------------------------------------------------------------------------------
    #   # Controle des prerequis
    #   if [ -d "${TOOLPATH}/tools" ]
    #   then
    #       echo ""
    #   elif [ -d /Library/Application Support/santesocial/CPS/tools ]
    #   then
    #       TOOLPATH="/Library/Application Support/santesocial/CPS/"
    #   else
    #       show_help
    #       echo ""
    #       echo -e "$ROUGE"" Prerequis manquant :"
    #       echo -e "  Le repertoire tools et son contenu ne sont pas presents !""$NORMAL"
    #       echo "La Cryptolib CPS n'est pas installée sur ce poste de travail."
    #       echo "Veuillez l'installer pour pouvoir utiliser ce script."
    #       echo ""
    #       exit 0
    #   fi

	# Suppression de l'extension Firefox
	DisplayStep " Suppression de l'extension Firefox"

	cd ~/Library/Application\ Support/Firefox/Profiles

	for profile in `find . -maxdepth 1 -type d`
	do
        if [ "$profile" != "." ]
        then
            # Changement du delimiteur de liste
            SAVEIFS=$IFS
            IFS=$':'

            DisplayTrace "  from profile $profile"
            USERPROFILE=$profile

            MODULE_FIREFOX_LIST=""
            MODULE_FIREFOX_LIST="$MODULE_FIREFOX_LIST:CPS PKCS11 sur GALSS"
            MODULE_FIREFOX_LIST="$MODULE_FIREFOX_LIST:Module de sécurité CPS"

            DisplayTrace "Suppression des modules de securite CPS sous Firefox"
            for i in $MODULE_FIREFOX_LIST
            do
                DisplayTrace "Suppression du certificat : ${i}"
#                sudo $TOOLPATH/tools/modutil -delete "$i" -dbdir "$USERPROFILE" -force  2> /dev/null
            done

            #$TOOLPATH/tools/modutil -delete "CPS PKCS11 sur GALSS" -dbdir "$USERPROFILE" -force  2> /dev/null
            #$TOOLPATH/tools/modutil -delete "Module de sÈcuritÈ CPS" -dbdir "$USERPROFILE" -force  2> /dev/null

            CERT_FIREFOX_LIST=""
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS ANONYME - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS PROFESSIONNEL - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS SERVEUR - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS STRUCTURE - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS STRUCTURE - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-2 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-3 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-3 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-1 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS ANONYME - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-0 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC-CLASSE-5 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC-CLASSE-4 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-1 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-2 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS CLASSE-0 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS PROFESSIONNEL - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:GIP-CPS SERVEUR - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC-CLASSE-6 - GIP-CPS"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:inscription.certif.gip-cps.fr - GIP-CPS"
            # Nouvelle IGC
                CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE ELEMENTAIRE ORGANISATIONS - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC RACINE IGC-SANTE FORT - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE FORT PERSONNES - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE ELEMENTAIRE PERSONNES - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE STANDARD PERSONNES - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC RACINE IGC-SANTE ELEMENTAIRE - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC RACINE IGC-SANTE STANDARD - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE STANDARD ORGANISATIONS - ASIP-SANTE"
            CERT_FIREFOX_LIST="$CERT_FIREFOX_LIST:AC IGC-SANTE FORT ORGANISATIONS - ASIP-SANTE"

            DisplayTrace "Suppression des certificats Firefox"
            for i in $CERT_FIREFOX_LIST
            do
                DisplayTrace "Suppression du certificat : ${i}"
#                sudo $TOOLPATH/tools/certutil -D -n "$i" -d "$USERPROFILE" 2> /dev/null
            done

            #$TOOLPATH/tools/certutil -D -n "GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS ANONYME - GIP-CPS" -d "$USERPROFILE"  2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS PROFESSIONNEL - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS SERVEUR - GIP-CPS"  -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS STRUCTURE - GIP-CPS"  -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS STRUCTURE - GIP-CPS"  -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-2 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-3 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-3 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-1 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS ANONYME - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-0 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC-CLASSE-5 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS"  -d "$USERPROFILE" 2> /dev/null 
            #$TOOLPATH/tools/certutil -D -n "AC-CLASSE-4 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-1 - GIP-CPS"  -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-2 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS CLASSE-0 - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS PROFESSIONNEL - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "GIP-CPS SERVEUR - GIP-CPS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC-CLASSE-6 - GIP-CPS"  -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "inscription.certif.gip-cps.fr - GIP-CPS"   -d "$USERPROFILE" 2> /dev/null

            # Nouvelle IGC
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE ELEMENTAIRE ORGANISATIONS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC RACINE IGC-SANTE FORT" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE FORT PERSONNES" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE ELEMENTAIRE PERSONNES" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE STANDARD PERSONNES" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC RACINE IGC-SANTE ELEMENTAIRE" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC RACINE IGC-SANTE STANDARD" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE STANDARD ORGANISATIONS" -d "$USERPROFILE" 2> /dev/null
            #$TOOLPATH/tools/certutil -D -n "AC IGC-SANTE FORT ORGANISATIONS" -d "$USERPROFILE" 2> /dev/null

            EXT_FIREFOX_LIST=""
            EXT_FIREFOX_LIST="$EXT_FIREFOX_LIST:$USERPROFILE/extensions/P11_CPS2ter_Firefox@asipsante.fr"
            EXT_FIREFOX_LIST="$EXT_FIREFOX_LIST:$USERPROFILE/extensions/P11_CPS3_Firefox@asipsante.fr"
            EXT_FIREFOX_LIST="$EXT_FIREFOX_LIST:$USERPROFILE/extensions/CPS2ter-2020_Firefox@asipsante.fr"

            DisplayTrace "Suppression des extensions Firefox"
            for i in $EXT_FIREFOX_LIST
            do
                DisplayTrace "Suppression de l'extension : ${i}"
                sudo rm -Rf "$i"
            done

            #rm -Rf "$USERPROFILE/extensions/P11_CPS2ter_Firefox@asipsante.fr"
            #rm -Rf "$USERPROFILE/extensions/P11_CPS3_Firefox@asipsante.fr"
            #rm -Rf "$USERPROFILE/extensions/CPS2ter-2020_Firefox@asipsante.fr"

            # Restauration du delimiteur de liste
            IFS=$SAVEIFS
        fi
	done
	cd -

	#-----------------------------------------------------------------------------------------
	# Passage en administrateur
	DisplayStep "Les droits administrateur sont necessaires"
	sudo echo "..."

	# Changement du delimiteur de liste
	SAVEIFS=$IFS
	IFS=$':'

	# Supprime les fichiers et les repertoires
	# Construction de la liste des fichiers 
	REMOVE_FILE_LIST=""
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Receipts/ApiCPS.pkg"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Receipts/CryptolibCPS.pkg" 
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Receipts/TokendCPS.pkg" 
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Receipts/CryptolibCPS-*.pkg" 
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Receipts/Certificats-CPS2ter2020.pkg"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/System/Library/LaunchDaemons/fr.asipsante.startpcscd.plist"
	# CPS2ter Filiere GALSS
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Java/Extensions/libJniCpsosx.jnilib"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/DICO-FR.GIP"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/cps_pkcs11_safe.ini"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/private/etc/reader.conf"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/private/etc/reader.gip"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/lib/libcps_pkcs11_osx.dylib"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Applications/inscpsst.ini"
	# CPS2ter Filiere Full PCSC
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/StartupItems/SmartcardServices/SmartcardServices"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/StartupItems/SmartcardServices/StartupParameters.plist"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/lib/libcps_pkcs11_pcsc_osx.dylib"
	# CPS3
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/lib/libcps3_pkcs11_osx.dylib"
	# Nouveaux chemins depuis OS X 10.11 El Capitan (Cryptolib CPS > 5.015)
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/local/lib/libcps_pkcs11_osx.dylib"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/local/lib/libcps_pkcs11_pcsc_osx.dylib"
	REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/usr/local/lib/libcps3_pkcs11_osx.dylib"

	# Construction de la liste des repertoires 
	REMOVE_DIR_LIST=""
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/cpsosx.framework"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/cptabosx.framework"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Preferences/santesocial/CPS"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/cpgesosx.app"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/usr/libexec/SmartCardServices/drivers/GALSSDriver.bundle"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/extensions/P11_CPS2ter_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/extensions/CPS2ter-2020_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/browser/extensions/P11_CPS2ter_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/browser/extensions/CPS2ter-2020_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/ApiCPS.pkg"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/CryptolibCPS.pkg" 
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/TokendCPS.pkg" 
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/CryptolibCPS-*.pkg"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/Certificats-CPS2ter2020.pkg"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/StartupItems/SmartcardServices"
	# CPS2ter Filiere GALSS
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/sscasosx.framework"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/System/Library/Security/tokend/GIP-CPS.tokend"
	# CPS2ter Filiere Full PCSC
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Preferences/santesocial/ChoixLecteur.app"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/System/Library/Security/tokend/GIP-CPS_PCSC.tokend" 
	# CPS3
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/cpgesosx_cps2.app"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/extensions/P11_CPS3_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/MacOS/browser/extensions/P11_CPS3_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/System/Library/Security/tokend/CPS3.tokend"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Application Support/santesocial/CPS"
	# Nouveaux chemins depuis OS X 10.11 El Capitan (Cryptolib CPS > 5.015)
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/usr/local/libexec/SmartCardServices/drivers/GALSSDriver.bundle"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Security/tokend/CPS3.tokend"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/Resources/browser/extensions/P11_CPS2ter_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Applications/Firefox.app/Contents/Resources/browser/extensions/CPS2ter-2020_Firefox@asipsante.fr"
	REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/PreferencePanes/PrefsCPS.prefPane"
		
	# Ajout de la liste des composants du GIE-SV
	if [ $GIESV -eq "1" ]
	then
		# Ajout a la liste des fichiers
		# GALSS
		if [ $CONFLECTEUR -eq "1" ]
		then
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/galss.ini"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/io_comm.ini"
		fi
		if [ $GALSS -eq "1" ]
		then
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/galss.ini.oldDMP*"
		fi
		# API de lecture Vitale
		if [ $APILEC -eq "1" ]
		then
			# Version 5
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/api_lec.ini"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/api_lec.ini.oldDMP*"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/sedica.ini"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/sedica.ini.oldDMP*"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/pdt-cdc-011.csv"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/tablebin.hab"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Library/Preferences/tablebin.lec"
			# Version 6
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/api_lec.ini"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/api_lecCv"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/pdt-cdc-011.csv"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/sedica.ini"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/tablebin.hab"
			REMOVE_FILE_LIST="$REMOVE_FILE_LIST:/Users/$USER/Library/Preferences/santesocial/DMP/tablebin.lec"
		fi
		
		# Ajout a la liste des repertoires
		# GALSS
		if [ $GALSS -eq "1" ]
		then
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Receipts/Galss.pkg"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Application support/galss"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/galclosx.framework"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/galssosx.framework"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/galinosx.framework"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/pssinosx.framework"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/pcscosx.framework"
		fi
		# API de lecture Vitale
		if [ $APILEC -eq "1" ]
		then
			# Version 5
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/api_lec.framework"
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Frameworks/Sedica.framework"
			# Version 6
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Users/$USER/Library/Preferences/santesocial/DMP"
		fi

		if [ $ALL -eq "1" ]
		then
			REMOVE_DIR_LIST="$REMOVE_DIR_LIST:/Library/Preferences/santesocial"
		fi
	fi

	# Construction de la liste des certificats
	#ACLIST=""
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/2008_03_17_IGC_CPS2bis_Exploit_Classe4_CertSign_CrlSign_Fin_2020.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/2008_03_17_IGC_CPS2bis_Exploit_Classe5_CertSign_CrlSign_Fin_2020.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/2008_03_17_IGC_CPS2bis_Exploit_Classe6_CertSign_CrlSign_Fin_2020.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/2008_03_17_IGC_CPS2bis_Exploit_Racine_CrlSign_Fin_2020.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CERTSIGN.EXPL.ANONYME.CL00.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CERTSIGN.EXPL.PROFESSIONNEL.CL01.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CERTSIGN.EXPL.STRUCTURE.CL02.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CERTSIGN.EXPL.STRUCTURE.CL03.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.ANONYME.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.ANONYME.CL00.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.PROFESSIONNEL.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.PROFESSIONNEL.CL01.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.SERVEUR.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.STRUCTURE.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.STRUCTURE.CL02.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/IGC-CPS.CRLSIGN.EXPL.STRUCTURE.CL03.cer"
	#ACLIST="$ACLIST /Library/Preferences/santesocial/CPS/coffre/inscription.certif.gip-cps.fr.cer"

	# Arret des Smartcard Services
	DisplayStep "Arret des Smartcard Services"
	StopProcess pcscd
	sudo launchctl unload -w /System/Library/LaunchDaemons/fr.asipsante.startpcscd.plist

	# Supprime les fichiers
	DisplayStep "Suppression des fichiers"
	for i in $REMOVE_FILE_LIST
	do
		DisplayTrace "Suppression du fichier : ${i}"
		sudo rm -f "$i"
	done

	# Supprime les repertoires
	DisplayStep "Suppression des repertoires"
	for i in $REMOVE_DIR_LIST
	do
		DisplayTrace "Suppression du repertoire : ${i}"
		sudo rm -Rf "$i"
	done

	# Suppression des certificats
	# Construction de la liste des empreintes
	CAPRINT=""
	CAPRINT="$CAPRINT:E63A4593BEB201C3623ACA426871D4D722E5D85C"
	CAPRINT="$CAPRINT:E4665C3BA1502BEBA5801D852A90435F22264820"
	CAPRINT="$CAPRINT:BF579BF334EA2A98D19C121D910F0C680742283A"
	CAPRINT="$CAPRINT:B24A516DE4377908EBA1DED7A230D1D72A2F4E27"
	CAPRINT="$CAPRINT:A168E150BAC31FBA0CD94E466F075B611EA2C867"
	CAPRINT="$CAPRINT:768D8492DCE0FB9E7E0A8A7C6C5E11E97D798FC2"
	CAPRINT="$CAPRINT:60110E694C33DCDD55A5F5AB23F56533E39F09F9"
	CAPRINT="$CAPRINT:5F3C2C90B974FE9FA8F9D2BDE11338C4D2681E37v"
	CAPRINT="$CAPRINT:4AC2FC4B4AD077669A9A6C4ACF8FA71810717407"
	CAPRINT="$CAPRINT:3182462F180AE880B6F43FA040CEC025DC2F2042"
	CAPRINT="$CAPRINT:26C2AE3328915DA3857BB838FD704E80255543FE"
	CAPRINT="$CAPRINT:1F26D93BD4B5F61E8FCE314CC16C81E5D3433A62"
	CAPRINT="$CAPRINT:169416B10CA2D2E2F6C206CA4868DCCB0FA03D9F"
	CAPRINT="$CAPRINT:1183A40ADE75F69B01888E6664E70D12CC46CFDD"
	CAPRINT="$CAPRINT:0A1B2BB0B39FBCFC440B1BA883F8498C571DBA84"
	CAPRINT="$CAPRINT:08C053B382E9D794FD7A9C44679B95E5C6B21B84"
	CAPRINT="$CAPRINT:668DA561BE01E13D5253E378DDD474DB0DBA8C51"

	CAPRINT="$CAPRINT:d031c6132a5345bcbc52c499b89b87e40a077bfe"
	CAPRINT="$CAPRINT:8a94bbbb12bd5567318fcf191b349b8ffd8a992d"
	CAPRINT="$CAPRINT:ba33690a8ac857d5e5514ac5fd817ee8ca1f7819"
	CAPRINT="$CAPRINT:9f92b6cbf7fc61ebea76f63add8d54c1ac2ddfb8"
	CAPRINT="$CAPRINT:46934c7cdad63c04b3fe76f5ffbf7512e55b8f7e"
	CAPRINT="$CAPRINT:bed257c7ac336aa2ac6dde832b2ea3d2e10fd6eb"
	CAPRINT="$CAPRINT:052a8a966d4bf1e9832d717d98ad35c14ec9119c"
	CAPRINT="$CAPRINT:5F3C2C90B974FE9FA8F9D2BDE11338C4D2681E37"
	CAPRINT="$CAPRINT:4AC2FC4B4AD077669A9A6C4ACF8FA71810717407"
	CAPRINT="$CAPRINT:3182462F180AE880B6F43FA040CEC025DC2F2042"
	CAPRINT="$CAPRINT:48630cfa410034e004a9bdb75d0ccb9df8eba4ac"
	CAPRINT="$CAPRINT:3e85e5f32c4c2e6f2d82884228c515ae73a5c8d7"
	CAPRINT="$CAPRINT:148d663d3f75ded92b5cb2608eea182ccfb1862e"
	CAPRINT="$CAPRINT:307e5e5cb30966f05df1670927a6154e91719ef3"
	
	# AC_ELEMENTAIRE_ORGANISATIONS_20130625
	CAPRINT="$CAPRINT:2cbfa991750af778348b3156c21609a1ab45a848"
	# AC_ELEMENTAIRE_PERSONNES_20130625
	CAPRINT="$CAPRINT:86a0de3d866e2db5095f6785a57fd5cc53b2f049"
	# AC_FORT_ORGANISATIONS_20130625
	CAPRINT="$CAPRINT:7c3af35b76fe34699fbc72c6a340bc7f1ac4d854"
	# AC_FORT_PERSONNES_20130625
	CAPRINT="$CAPRINT:aa6131e760b95622c0f4c2aa9d985002c21f3a0c"
	# AC_STANDARD_ORGANISATIONS_20130625
	CAPRINT="$CAPRINT:ea8752036e115ee8aa1653672289074a24b23994"
	# AC_STANDARD_PERSONNES_20130625
	CAPRINT="$CAPRINT:e0d6e1d8481fed62c65c53ed9dfcda949c3d1d81"

	ROOTCAPRINT=""
	ROOTCAPRINT="$ROOTCAPRINT:8E4471D30842B54BC7E2582770009469ABD02CC7"
	ROOTCAPRINT="$ROOTCAPRINT:552c001b751b326acccdfe9a6f1148adcc687816"
	ROOTCAPRINT="$ROOTCAPRINT:9956634ad724f00a18c479e56463c6fb1c7a073d"
	ROOTCAPRINT="$ROOTCAPRINT:514f46f3e278fbf6d8268286e19adee0cc443642"
	# ACR_ELEMENTAIRE_20130625
	ROOTCAPRINT="$ROOTCAPRINT:4b23d44dc5cbda230fc052dff52407edaf373c69"
	# ACR_FORT_20130625
	ROOTCAPRINT="$ROOTCAPRINT:bbe751c8b107acd29f7d12e0fcdd717e00138764"
	# ACR_STANDARD_20130625
	ROOTCAPRINT="$ROOTCAPRINT:b6ba1d6d5224bceda95a67f6f37b86896edd0006"	

	# Supprime les certificats d'AC
	DisplayStep "Suppression des certificats d'AC"
	for i in $CAPRINT
	do
		DisplayTrace "Suppression du certificat : ${i}"
		sudo security delete-certificate -Z $i /System/Library/Keychains/SystemCACertificates.keychain
		echo ""
	done

	# Supprime les certificats de Root AC
	DisplayStep "Suppression des certificats de Root AC"
	for i in $ROOTCAPRINT
	do
		DisplayTrace "Suppression du certificat de Root AC : ${i}"
		sudo security delete-certificate -Z $i /System/Library/Keychains/SystemRootCertificates.keychain
		echo ""
	done

	# Suppression des references aux packages
	# Construction de la liste des packages
	PKGREF=""
	PKGREF="$PKGREF:org.asipsante.cryptolibCPS"
	PKGREF="$PKGREF:com.gipcps.apicps"
	PKGREF="$PKGREF:com.gipcps.cryptolib"
	PKGREF="$PKGREF:com.gipcps.tokend"
	PKGREF="$PKGREF:fr.asipsante.pkg.cryptolibCPS"
	PKGREF="$PKGREF:gip-cps.fr.cryptolib.pcsc.pkg"
	PKGREF="$PKGREF:fr.asipsante.pkg.certificats-CPS2ter2020"

	# Package GIE-SV
	if [ $GIESV -eq "1" ]
	then
		# GALSS
		if [ $GALSS -eq "1" ]
		then
			PKGREF="$PKGREF:fr.sesamvitale.galss.pkg"
			PKGREF="$PKGREF:com.gipcps.galss"
		fi
	fi

	DisplayStep "Suppression de la reference aux packages"
	for i in $PKGREF
	do
		DisplayTrace "Suppression de la reference au package : ${i}"
		sudo pkgutil --forget $i 2>/dev/null
	done

	# Restauration du delimiteur de liste
	IFS=$SAVEIFS

	DisplayStep "Suppression des fichiers ADM"
	ProcessCleanADMs

else
	#-----------------------------------------------------------------------------------------
	# Passage en administrateur
	DisplayStep "Les droits administrateur sont necessaires"
	sudo echo "..."
	
	# Changement du delimiteur de liste
	SAVEIFS=$IFS
	IFS=$':'
	
	# Cas du traitement du Tokend
	#-----------------------------------------------------------------------------------------
	if [ $TOKEND -eq "1" ]	
	then
		DisplayStep "Traitement du Tokend"
	
		TOKEND_LIST=""
		TOKEND_LIST="$TOKEND_LIST:/System/Library/Security/tokend/GIP-CPS.tokend"
		TOKEND_LIST="$TOKEND_LIST:/System/Library/Security/tokend/GIP-CPS_PCSC.tokend"
		TOKEND_LIST="$TOKEND_LIST:/System/Library/Security/tokend/CPS3.tokend"
		# Nouveaux chemins depuis OS X 10.11 El Capitan (Cryptolib CPS > 5.015)
		TOKEND_LIST="$TOKEND_LIST:/Library/Security/tokend/CPS3.tokend"

		if [ $TOKEND_ACTIVE -eq "1" ]
		then
			for i in $TOKEND_LIST
			do
				DisplayTrace "Activation du Tokend"
				sudo mv -f $i.deactivate $i
			done
		else
			for i in $TOKEND_LIST
			do
				DisplayTrace "Desactivation du Tokend"
				sudo mv -f $i $i.deactivate
				#rm -Rf $i
			done
		fi
	fi
	
	# Cas du traitement du fr.asipsante.startpcscd.plist
	#-----------------------------------------------------------------------------------------	
	if [ $PCSCDAUTO -eq "1" ]
	then
		DisplayStep "Traitement de l’activation du chargement automatique de pcscd"
		
		if [ $PCSCDAUTO_ACTIVE -eq "1" ]
		then
			DisplayTrace "Activation du lien"
			sudo launchctl load -w /System/Library/LaunchDaemons/fr.asipsante.startpcscd.plist
		else
			DisplayTrace "Desactivation du lien"
			sudo launchctl unload -w /System/Library/LaunchDaemons/fr.asipsante.startpcscd.plist
		fi
	fi

	# Cas du traitement du reader.conf
	#-----------------------------------------------------------------------------------------	
	if [ $READERCFG -eq "1" ]
	then
		DisplayStep "Traitement du lien PSS vers PC/SC (reader.conf)"
		
        MACOSVER_MAJ=`sw_vers -productVersion | cut -d . -f 2`
        
        CPSPATHTOKEND="/Library/Security/tokend"
        CPSPATHGLASSDRIVER="/usr/local/libexec/SmartCardServices/drivers"
        
        # Older Mac OS X
        if [ $MACOSVER_MAJ -lt 11 ]
        then
            DisplayTrace "Older Mac OS X"
            CPSPATHTOKEND="/System/Library/Security/tokend"
            CPSPATHGLASSDRIVER="/usr/libexec/SmartCardServices/drivers"
        fi
        
		READER_FILE="/private/etc/reader"
		if [ $READERCFG_ACTIVE -eq "1" ]
		then
			DisplayTrace "Activation du lien"
			sudo mv -f $READER_FILE.gip $READER_FILE.conf
			sudo rm -f $READER_FILE.gi*
            
            sudo mv -f ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist.deactivate ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
		else
			DisplayTrace "Desactivation du lien"
			sudo mv -f $READER_FILE.conf $READER_FILE.gip
			sudo cp -f $READER_FILE.gip $READER_FILE.gie
            
            sudo mv -f ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist.deactivate
		fi
	fi
	
	# Cas de la suppression des logs
	#-----------------------------------------------------------------------------------------	
	if [ $LOG_ASIP_DEL -eq "1" ]
	then
		DisplayStep "Suppression des logs de la Cryptolib CPS"
		
		sudo rm /Library/Logs/santesocial/CPS/*
	fi
	
	if [ $LOG_GIE_DEL -eq "1" ]
	then
		DisplayStep "Suppression des logs du GALSS"
		
		sudo rm /Library/Logs/santesocial/galss/*
	fi

	# Cas de la suppression des caches
	#-----------------------------------------------------------------------------------------	
	if [ $CACHE_CPS_DEL -eq "1" ]
	then
		DisplayStep "Suppression des caches de CPS"
		
		sudo rm /Library/Caches/santesocial/CPS/*
	fi

	# Cas de la configuration CPS3
	#-----------------------------------------------------------------------------------------	
	if [ $CONF_CPS3 -eq "1" ]
	then
        MACOSVER_MAJ=`sw_vers -productVersion | cut -d . -f 2`
        
        CPSPATHTOKEND="/Library/Security/tokend"
        CPSPATHGLASSDRIVER="/usr/local/libexec/SmartCardServices/drivers"
        
        # Older Mac OS X
        if [ $MACOSVER_MAJ -lt 11 ]
        then
            DisplayTrace "Older Mac OS X"
            CPSPATHTOKEND="/System/Library/Security/tokend"
            CPSPATHGLASSDRIVER="/usr/libexec/SmartCardServices/drivers"
        fi
        
        if [ -n "$TRACES_ACTIVE" ]
        then
            LINENB_TOKEND=`sudo sed -n '/LogEnable/=' ${CPSPATHTOKEND}/CPS3.tokend/Contents/Info.plist`
            LINENB_TOKEND=`expr $LINENB_TOKEND + 1`

            LINENB_LOGLEVEL=`sudo sed -n '/ifdLogLevel/=' ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist`
            LINENB_LOGLEVEL=`expr $LINENB_LOGLEVEL + 1`

            LINENB_LOGPERIODIC=`sudo sed -n '/ifdLogPeriodic/=' ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist`
            LINENB_LOGPERIODIC=`expr $LINENB_LOGPERIODIC + 1`

            DisplayStep "Configuration CPS3 PKC11"
            printf "Sign_Hash\n{\n\tactive = $SIGN_HASH;\n}\n" | sudo tee /Library/Preferences/santesocial/CPS/cps3_pkcs11.conf

            if [ $TRACES_ACTIVE == "true" ]
            then
                DisplayStep "Activation des traces PKCS11"
                # traces PKCS11
                printf "traces\n{\n\tactive = $TRACES_ACTIVE;\n\tdebug = 10;\n}\n" | sudo tee -a /Library/Preferences/santesocial/CPS/cps3_pkcs11.conf

                # traces Tokend
                DisplayStep "Activation des traces Tokend"
                sudo sed -i -e "${LINENB_TOKEND}s/<string>.*<\/string>/<string>Y<\/string>/" ${CPSPATHTOKEND}/CPS3.tokend/Contents/Info.plist

                # traces GALSSDriver
                DisplayStep "Activation des traces GALSSDriver"
                sudo sed -i -e "${LINENB_LOGLEVEL}s/<string>.*<\/string>/<string>255<\/string>/" ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
                sudo sed -i -e "${LINENB_LOGPERIODIC}s/<string>.*<\/string>/<string>Y<\/string>/" ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
            fi
            if [ $TRACES_ACTIVE == "false" ]
            then
                DisplayStep "Desactivation des traces PKCS11, Tokend et GALSSDriver"
                # traces Tokend
                sudo sed -i -e "${LINENB_TOKEND}s/<string>.*<\/string>/<string>N<\/string>/" ${CPSPATHTOKEND}/CPS3.tokend/Contents/Info.plist

                # traces GALSSDriver
                sudo sed -i -e "${LINENB_LOGLEVEL}s/<string>.*<\/string>/<string>0<\/string>/" ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
                sudo sed -i -e "${LINENB_LOGPERIODIC}s/<string>.*<\/string>/<string>N<\/string>/" ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
            fi
        fi
        
        if [ -n "$STARTUPDELAY" ]
        then
            DisplayStep "Modification du delai de chargement du TokenD aprs un demarrage du poste de travail"
            LINENB_STARTUPDELAY=`sudo sed -n '/ifdStartupDelay/=' ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist`
            LINENB_STARTUPDELAY=`expr $LINENB_STARTUPDELAY + 1`
            
            case $STARTUPDELAY in
                change) STARTUPDELAY_VALUE=2
                    echo -e "Entrez une valeur en secondes pour le delai de chargement du TokenD apres un demarrage du poste de travail,"
                    echo -n -e "i.e. ""$BOLD""ifdStartupDelay""$NORMAL"", puis validez [max. 99, par defaut 2] : "
                    read VALUE
                    if [ -n "$VALUE" ]
                    then
                        STARTUPDELAY_VALUE=$VALUE
                    fi
                    ;;
                usine) STARTUPDELAY_VALUE=0
                    ;;
                *) STARTUPDELAY_VALUE=$STARTUPDELAY
                    ;;
            esac
            if [[ "$STARTUPDELAY_VALUE" =~ ^[0-9]+$ ]] && [ $STARTUPDELAY_VALUE -lt 100 ]
            then
                sudo sed -i '' -e "${LINENB_STARTUPDELAY}s/<string>.*<\/string>/<string>${STARTUPDELAY_VALUE}<\/string>/" ${CPSPATHGLASSDRIVER}/GALSSDriver.bundle/Contents/Info.plist
            else
                echo ""
                echo -e "$ROUGE""Erreur : la valeur n'est pas numerique ou superieure a 99 !""$NORMAL"
                echo ""
                exit 0
            fi
        fi

    fi
    
    # Cas de la configuration du GALSS
	#-----------------------------------------------------------------------------------------	
	if [ $CONF_GALSS -eq "1" ]
	then
        DisplayStep "Configuration GALSS"
        sudo LC_CTYPE=C sed -i -e "s/priority=\".*\" /priority=\"${TRACES_GALSS_ACTIVE}\" /" "/Library/Application Support/santesocial/galss/log4crc.xml"
        
        DisplayStep "Kill GALSS Serveur"
        sudo killall galsvosx
    fi

	# Cas du debug
	#-----------------------------------------------------------------------------------------	
	HORODATE=`date +"%y%m%d%H%M%S"`
	
	if [ $DEBUG_SPINDUMP -eq "1" ]
	then
		DisplayStep "Debug : spindump dans spindump_$HORODATE.txt"
		sudo spindump -notarget 120 10 -file /Library/Logs/santesocial/CPS/spindump_$HORODATE.txt
	fi
    
	if [ $DEBUG_SYSDIAGNOSE -eq "1" ]
	then
		DisplayStep "Debug : sysdiagnose"
		sudo sysdiagnose -f /Library/Logs/santesocial/CPS/
	fi

	if [ $DEBUG_INFOSYS -eq "1" ]
	then
		DisplayStep "Debug : Recuperation des informations systemes"
        
        printf 'Informations du systeme MacOS\n==================================\n' | tee system_infos.txt
        
        printf '\nUtilisateur courant (whoami)\n----------------------------------\n'  | tee -a system_infos.txt
        whoami >> system_infos.txt
        echo "Recuperation 1/6"
        
        printf '\nMac OS X versions (sw_vers)\n----------------------------------\n' | tee -a system_infos.txt
        sw_vers >> system_infos.txt
        echo "Recuperation 2/6"
        
        printf '\nMac OS X Kernel (uname -av)\n----------------------------------\n' | tee -a system_infos.txt
        uname -av >> system_infos.txt
        echo "Recuperation 3/6"
        
        printf '\nEtat de l espace sur les disques (df -H)\n----------------------------------\n' | tee -a system_infos.txt
        df -H >> system_infos.txt
        echo "Recuperation 4/6"
        
        printf '\n/System/Library/CoreServices/SystemVersion.plist\n----------------------------------\n' | tee -a system_infos.txt
        cat /System/Library/CoreServices/SystemVersion.plist >>system_infos.txt
        echo "Recuperation 5/6"
        
        printf '\nsystem_profiler\n----------------------------------\n' | tee -a system_infos.txt
        system_profiler -detailLevel basic >> system_infos.txt
        echo "Recuperation 6/6"
                
        sudo mv system_infos.txt /Library/Logs/santesocial/CPS/
        
        if [ $ZIP_INFOS -eq "0" ]
        then
            cat /Library/Logs/santesocial/CPS/system_infos.txt | more
        fi
	fi

	# Cas du debug
	#-----------------------------------------------------------------------------------------	
	if [ $ZIP_INFOS -eq "1" ]
	then
		DisplayStep "Archive : zip logs/spindump/sysdiagnose dans logs_santesocial_$HORODATE.zip"
				
        sudo zip -r logs_santesocial_$HORODATE.zip /Library/Logs/santesocial
        
        if [ $DEBUG_SPINDUMP -eq "1" ]
        then
            sudo zip logs_santesocial_$HORODATE.zip /Library/Logs/santesocial/CPS/spindump_$HORODATE.txt
        fi
	fi

	# Restauration du delimiteur de liste
	IFS=$SAVEIFS	
fi

echo ""
echo -e "$VERT""Termine ...""$NORMAL"
echo ""

exit

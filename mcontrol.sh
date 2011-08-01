#!/bin/bash
# Website: http://wiki.natenom.name/minecraft/serverscript
# Version 0.0.7 - 2011-07-31
# Natenom natenom@natenom.name
# License: Attribution-NonCommercial-ShareAlike 3.0 Unported
#
# Based on Script taken from http://www.minecraftwiki.net/wiki/Server_startup_script version 0.3.2 2011-01-27 (YYYY-MM-DD)
# Original License: Attribution-NonCommercial-ShareAlike 3.0 Unported
#
# + MultiServer kompatibel, auch pro Benutzer
# + improve check if server is running
# + usage of Vars instead of using same shit again and again :/
# + optional quota support (extra script)

LC_LANG=C

############# Settings #####################
QUOTA_HANDLER="/usr/local/bin/backupquota3.sh" #handles Backup Quota ...

# Can be "tar" or "rdiff"
# Be sure to install rdiff-backup http://www.nongnu.org/rdiff-backup/ in case of rdiff :)
BACKUPSYSTEM="tar"
########### End: Settings ##################


############################################
##### DO NOT EDIT BELOW THIS LINE ##########
#Read user settings from /etc/minecraft-server/<username>/<servername>
SETTINGS_FILE=${1}

#Check if settings file is in /etc/minecraft-server
#FIXME

. "${SETTINGS_FILE}"

MCSERVERID="mc-server-${RUNAS}-${SERVERNAME}" #Unique ID to be able to send commands to a screen session.
INVOCATION="java -Xincgc -Xmx${MAX_GB}G -jar ${JAR_FILE}"

#FIXME
#case ${SERVER_TYPE} in
#    vanilla)
#        #INVOCATION="java -Xmx1024M -Xms1024M -XX:+UseConcMarkSweepGC -XX:+CMSIncrementalPacing -XX:ParallelGCThreads=$CPU_COUNT -XX:+AggressiveOpts -jar craftbukkit.jar nogui"
#	;;
#    bukkit)
#INVOCATION="java -Xincgc -Xmx1G -jar ${JAR_FILE}"
#	;;
#esac

function check_quota() {
#uses only lines with xx GB
        local quota=$1

        RDIFFBACKUP_LIST=$(rdiff-backup --list-increment-sizes ${BACKUPDIR}/${SERVERNAME}-rdiff | sed = - | sed 'N;s/\n/\t/' | sed -nr -e 's/^([0-9]+).*([a-zA-Z]{3} [a-zA-Z]{3} [0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}).*([0-9]+\.[0-9]{2}) GB$/\1 \3/p' )
        IFS='
'
        for i in $RDIFFBACKUP_LIST
        do  
                local BACKUPNUMBER=$(($(echo $i | cut -d' ' -f1)-2))
                #-2 weil die ersten beiden Zeilen Ueberschrift und Trennlinie sind.
            
                local CUMMULSIZE=$(echo $i | cut -d' ' -f2)
            
                #umrechnen in MiBytes und die nachkommestellen abschneiden
                local SIZE_MiB=$(echo "$CUMMULSIZE * 1024" | bc -q | sed -nr -e 's/^(.*)\..*$/\1/p')
            
                #printf "BackupNr: %s, SizeMiB: %s\n" "$BACKUPNUMBER" "$SIZE_MiB"
                if [ $SIZE_MiB -gt $quota ];
                then
                        #echo "loeschen ab backupnr $BACKUPNUMBER"
			#BACKUPNUMBER is now the first backup that breaks quota; return BACKUPNUMBER-1 to remove it.
                        echo $(($BACKUPNUMBER-1))
			return 0
                fi  
        done
	return 1 #something went wrong...
}


function as_user() {
  if [ "$(whoami)" = "${RUNAS}" ] ; then
    /bin/bash -c "$1"
  else
    su - ${RUNAS} -c "$1"
  fi
}

function is_running() {
   if ps aux | grep -v grep | grep SCREEN | grep "${MCSERVERID}" >/dev/null 2>&1
   then
     return 0 #is running, exit level 0 for everythings fine...
   else
     return 1 #is not running
   fi

}

function mc_start() {
  if is_running 
  then
    echo "Tried to start but ${JAR_FILE} was already running!"
  elif [ -f "${SERVERDIR}/${DONT_START}" ]
  then
    echo "Tried to start but ${DONT_START} exists."
  else
    echo "${JAR_FILE} was not running... starting."
    cd "${SERVERDIR}"
    as_user "cd ${SERVERDIR} && screen -dmS ${MCSERVERID} ${INVOCATION}"
    sleep 3

    if is_running
    then
      echo "${JAR_FILE} is now running."
    else
      echo "Could not start ${JAR_FILE}."
    fi
  fi
}

function mc_saveoff() {
        if is_running
	then
		echo "${JAR_FILE} is running... suspending saves"
		as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say Server-Backup wird gestartet.\"\015'"
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-off\"\015'"
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-all\"\015'"
                sync
		sleep 10
	else
                echo "${JAR_FILE} was not running. Not suspending saves."
	fi
}

function mc_saveon() {
 	if is_running
	then
		echo "${JAR_FILE} is running... re-enabling saves"
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-on\"\015'"
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say Server-Backup ist fertig.\"\015'"
	else
                echo "${JAR_FILE} was not running. Not resuming saves."
	fi
}

function mc_stop() {
        if is_running
        then
                echo "${JAR_FILE} is running... stopping."
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say Server wird in 10 Sekunden heruntergefahren. Map wird gesichert...\"\015'"
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-all\"\015'"
                sleep 10
                as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"stop\"\015'"
                sleep 7
        else
                echo "${JAR_FILE} was not running."
        fi

 	if is_running
        then
                echo "${JAR_FILE} could not be shut down... still running."
        else
                echo "${JAR_FILE} is shut down."
        fi
}

function mc_backup() {
   [ -d "${BACKUPDIR}" ] || mkdir -p "${BACKUPDIR}"
   echo "Backing up ${MCSERVERID}."

   case ${BACKUPSYSTEM} in
        tar)
	   # Wir erstellen pro Tag ein Unterverzeichnis im Backupverzeichnis. Name ist das Datum. Falls dann quota voll ist, werden ja Verzeichnisse in der Hauptebene geloescht, also dann immer ganze Tagesbackups.
	   # Wenn fuer den aktuellen Tag noch kein Verzeichnis existiert, dann legen wir es an und machen ein initiales komplettes Backup.
	   # Existiert der Ordner bereits, dann koennen wir davon ausgehen, dass ein Komplettbackup existiert und auch eine snapshot datei und machen ein inkrementelles Backup.

	   DATE=$(date "+%Y-%m-%d")
	   TIME=$(date "+%H-%M-%S")
	   THISBACKUP="${BACKUPDIR}/${DATE}" #Our current backup destiny.

	   [ -d "${THISBACKUP}" ] || mkdir -p "${THISBACKUP}" # Create daily directory if it does not exist.


	   TAR_SNAP_FILE="${THISBACKUP}/${SERVERNAME}.snap" #Snapshot file for tar, with meta information.
	   [ -f "${TAR_SNAP_FILE}" ] && BACKUP_TYPE="inc" || BACKUP_TYPE="full" #If DIR for today exists, do incremental, else full backup.

	   #Create backup tar.
	   TAR_FILE="${THISBACKUP}/${SERVERNAME}.${TIME}.${BACKUP_TYPE}.tar"
	   as_user "cd && tar -cvf '${TAR_FILE}' -g '${TAR_SNAP_FILE}' '${SERVERDIR}' > /dev/null 2>&1"

	   #Etwas anders ..., da wir erst die Datei ablegen und dann eventuell loeschen um Quota einzuhalten, aber funktioniert :)
	   # !!! Every Server should have its own Backupdirectory..., sonst gilt ein Quota fuer die Backupverzeichnisse aller Server :P !!!
	   if [ -f "${QUOTA_HANDLER}" ]
	   then
	       . /usr/local/bin/backupquota3.sh
	       as_user "checkdir '${BACKUPDIR}' '${BACKUP_QUOTA_MiB}' '${TAR_FILE}'" #nach diesem Aufruf ist sicher gestellt, dass mitsamt neuer Datei das Quota unterschritten bleibt :)
	   fi
	  ;;
	rdiff)
	   rdiff-backup "${SERVERDIR}" "${BACKUPDIR}/${SERVERNAME}-rdiff"
	
	   #now check if within quota; a very simple implementation; works only if running always; will not delete more than one old backup...bla
	   local REMOVE_STARTING_AT=$(check_quota ${BACKUP_QUOTA_MiB})
	   if [ ! -z "${REMOVE_STARTING_AT}" ]
	   then
		rdiff-backup --remove-older-than ${REMOVE_STARTING_AT}B "${BACKUPDIR}/${SERVERNAME}-rdiff" #If something goes really wrong, rdiff-backup deletes only one backup per call ... if not used with --force
	   else
 	 	echo "Quota OK. (If you are sure, that quota bla, check function quota_check.)"
	   fi

	  ;;
   esac
}

function listbackups() {
	if [ "${BACKUPSYSTEM}" != "rdiff" ]
	then
		echo "Error: listbackups is only available for usage with rdiff-backup; change BACKUPSYSTEM in \"$0\" or in user-settings-file in order to use rdiff-backup."
	else
		echo "Backups for server \"${SERVERNAME}\""
		rdiff-backup -l "${BACKUPDIR}/${SERVERNAME}-rdiff"
		rdiff-backup --list-increment-sizes "${BACKUPDIR}/${SERVERNAME}-rdiff"
	fi
}

#Start-Stop here
case "${2}" in
  start)
    mc_start
    ;;
  isrunning)
    is_running
    ;;
  stop)
    mc_stop
    ;;
  restart)
    mc_stop
    mc_start
    ;;
  listbackups)
    listbackups
    ;;
#  update)
#    mc_stop
#    mc_backup
#    mc_update
#    mc_start
#    ;;
  backup)
    mc_saveoff
    mc_backup
    mc_saveon
    ;;
  status)
    if is_running
    then
      echo "${JAR_FILE} is running."
    else
      echo "${JAR_FILE} is not running."
    fi
    ;;
  sendcommand|sc|c)
	if is_running
	then
		screen -S "$MCSERVERID" -p 0 -X stuff "$(printf "${3}\r")"
	fi
    ;;
  *)cat << EOHELP
Usage: ${0} SETTINGS_FILE OPTION [ARGUMENT]
For example: ${0} /etc/minecraft-server/userx/serverx-bukkit status

OPTIONS
    start              Start the server.
    stop               Stop the server.
    restart            Restart the server.
    backup             Backup the server.
    listbackups        List current inkremental backups (only available for BACKUPSYSTEM="rdiff").
    status             Prints current status of the server (online/offline)
    sendcommand|sc|c   Send command to the server given as [ARGUMENT]

EXAMPLES
    Send a message to all players on the server:
    ${0} SETTINGS_FILE sendcommand "say We are watching you :P"

EOHELP
    exit 1

  ;;
esac

exit 0

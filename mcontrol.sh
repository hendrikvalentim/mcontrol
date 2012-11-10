#!/bin/bash
# Website: http://wiki.natenom.name/minecraft/mcontrol
# Natenom natenom@natenom.name
# License: Attribution-NonCommercial-ShareAlike 3.0 Unported
#
# Based on Script taken from http://www.minecraftwiki.net/wiki/Server_startup_script version 0.3.2 2011-01-27 (YYYY-MM-DD)
# Original License: Attribution-NonCommercial-ShareAlike 3.0 Unported

############# Settings #####################
# Default backup system, if not specified in serversettings.
# Can be "tar" or "rdiff"
# Be sure to install rdiff-backup http://www.nongnu.org/rdiff-backup/ in case of rdiff :)

BACKUPSYSTEM="rdiff"

MC_SERVER_LANG="de_DE.UTF-8" #use localized messages (e.g. for AFK Status) for Ingame-Messages; C or empty for default.

RUNSERVER_NICE=""   #run Server with nicelevel (complete command needed, e.g. RUNSERVER_NICE="nice -n19")
RUNSERVER_TASKSET="" #Set CPU affinity of a server with taskset command, e.g. TASKSET="taskset -c 1"

RUNBACKUP_NICE="nice -n19"   #run Backup with nicelevel (complete command needed, e.g. RUNBACKUP_NICE="nice -n19")
RUNBACKUP_IONICE="ionice -c 3" #only relevant for backup

ID_LIST=/home/minecraft/id.list
ID_LIST_NAMES=/home/minecraft/id.list-names

BIN_JAVA="java"
BIN_RDIFF="rdiff-backup"

PRINT_COUNTTOWN="true" #If true, prints 'SAY_SERVER_STOP_COUNTDOWN resttime' to the server on shutdown.

#Strings
SAY_BACKUP_START="Server-Backup wird gestartet."
SAY_BACKUP_FINISHED="Server-Backup ist fertig."
SAY_SERVER_STOP="Server wird in ###sec### Sekunden heruntergefahren. Karte wird gesichert." ###sec### will be replaced by time to shutdown

SAY_SERVER_STOP_COUNTDOWN="Shutdown des Servers in ###sec### Sekunden." ###sec### will be replaced by remaining time in seconds.
TERMUXER="screen"             # Can be screen or tmux

WAIT_BEFORE_KILL=10
########### End: Settings ##################


############################################
##### DO NOT EDIT BELOW THIS LINE ##########
#This is important to have always the same output format.
LC_LANG=C

#Read user settings from /etc/minecraft-server/<username>/<servername>
SETTINGS_FILE=${1}
  #Check if settings file is in /etc/minecraft-server and if user has no write permission on it; if not, warn and exit...
  #FIXME

. "${SETTINGS_FILE}"

MCSERVERID="mc-server-${RUNAS}-${SERVERNAME}" #Unique ID to be able to send commands to a screen session.
INVOCATION="${BIN_JAVA} -Xincgc -XX:ParallelGCThreads=$CPU_COUNT -Xmx${MAX_RAM} -jar ${JAR_FILE}"

WAITTIME_BEFORE_SHUTDOWN=10 #After warning "server shutdown" wait this time before shutdown.

#INVOCATION="java -Xmx1024M -Xms1024M -XX:+UseConcMarkSweepGC -XX:+CMSIncrementalPacing -XX:ParallelGCThreads=$CPU_COUNT -XX:+AggressiveOpts -jar craftbukkit.jar nogui"

# This is an easy implementation of quota:
#  - check size of all backups with du -s ...
#  - if size>quota, then start remove-loop and remove so long the oldest backup, until size<=quota
#   sooo einfach :)
function trim_to_quota() {
        [ ${DODEBUG} -eq 1 ] && set -x
	local quota=$1
	local _backup_dir="${BACKUPDIR}/${SERVERNAME}-rdiff"
	_size_of_all_backups=$(($(du -s ${_backup_dir} | cut -f1)/1024))

	while [ ${_size_of_all_backups} -gt $quota ];
	do
		echo ""
		echo "Total backup size of ${_size_of_all_backups} MiB has reached quota of $quota MiB."
		local _increment_count=$(($(${BIN_RDIFF} --list-increments ${_backup_dir}| grep -o increments\. | wc -l)-1))
		echo "  going to --force --remove-older-than $((${_increment_count}-1))B"
		${RUNBACKUP_NICE} ${RUNBACKUP_IONICE} ${BIN_RDIFF} --force --remove-older-than $((${_increment_count}-1))B "${BACKUPDIR}/${SERVERNAME}-rdiff" >/dev/null 2>&1
		echo "  Removed."
		_size_of_all_backups=$(($(du -s ${_backup_dir} | cut -f1)/1024))
	done
	echo "Total backup size (${_size_of_all_backups} MiB) is less or equal quota ($quota MiB)."
}

#Checks, if the serverdir is inside a ramdisk (tmpfs mountpoint)
function is_ramdisk() {
    [ ${DODEBUG} -eq 1 ] && set -x
    stat -f ${SERVERDIR} | grep tmpfs >/dev/null 2>&1
}

function as_user() {
  [ ${DODEBUG} -eq 1 ] && set -x
  if [ "$(whoami)" = "${RUNAS}" ] ; then
    /bin/bash -c "$1" 
  else
    su - ${RUNAS} -c "$1"
  fi
}

function is_running() {
   [ ${DODEBUG} -eq 1 ] && set -x
   if [ "${TERMUXER}" = "screen" ]; then
       local _grepit="SCREEN" #needs to be upper case
       if ps aux | grep -v grep | grep ${_grepit} | grep "${MCSERVERID} " >/dev/null 2>&1 #Das Leerzeichen am Ende des letzten grep, damit lalas1 und lalas1-test unterschieden werden.
       then
         return 0 #is running, exit level 0 for everythings fine...
       else
         return 1 #is not running
       fi  
   else
       if $(tmux list-sessions | grep -v grep | grep "^${MCSERVERID}" >/dev/null 2>&1)
       then
         return 0 #is running, exit level 0 for everythings fine...
       else
         return 1 #is not running
       fi  
   fi  
}

function mc_start() {
  [ ${DODEBUG} -eq 1 ] && set -x
# Add checks if ramdis and if ismounted...

  if is_running 
  then
    echo "Tried to start but ${JAR_FILE} is already running!"
  elif [ -f "${SERVERDIR}/${DONT_START}" ]
  then
    echo "Tried to start but ${DONT_START} exists."
  else
    echo "${JAR_FILE} is not running... starting."
    cd "${SERVERDIR}"
    
    if [ "${TERMUXER}" = "screen" ]; then
        as_user "export LC_ALL=${MC_SERVER_LANG}; cd ${SERVERDIR} && screen -dmS ${MCSERVERID} ${RUNSERVER_TASKSET} ${RUNSERVER_NICE} ${INVOCATION}"
    else
        as_user "export LC_ALL=${MC_SERVER_LANG}; cd ${SERVERDIR} && tmux new-session -s ${MCSERVERID} -d ""'""${RUNSERVER_TASKSET} ${RUNSERVER_NICE} ${INVOCATION}""'"
    fi
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
        [ ${DODEBUG} -eq 1 ] && set -x
        if is_running
	then
		echo "${JAR_FILE} is running... suspending saves"

    		if [ "${TERMUXER}" = "screen" ]; then
		    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say ${SAY_BACKUP_START}\"\015'"
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-off\"\015'"
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-all\"\015'"
		else
		    as_user "tmux send-keys -t ${MCSERVERID} 'say \"${SAY_BACKUP_START}\"'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
			
                    as_user "tmux send-keys -t ${MCSERVERID} 'save-off'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
                    as_user "tmux send-keys -t ${MCSERVERID} 'save-all'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
		fi 
                sync
		sleep 10
	else
                echo "${JAR_FILE} was not running. Not suspending saves."
	fi
}

function mc_saveon() {
        [ ${DODEBUG} -eq 1 ] && set -x
 	if is_running
	then
		echo "${JAR_FILE} is running... re-enabling saves"
    		if [ "${TERMUXER}" = "screen" ]; then
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-on\"\015'"
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say ${SAY_BACKUP_FINISHED}\"\015'"
		else
                    as_user "tmux send-keys -t ${MCSERVERID} 'save-on'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
                    as_user "tmux send-keys -t ${MCSERVERID} 'say \"${SAY_BACKUP_FINISHED}\"'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
		fi
	else
                echo "${JAR_FILE} was not running. Not resuming saves."
	fi
}

function get_server_pid() {
                [ ${DODEBUG} -eq 1 ] && set -x
		#get pid of screen
    		if [ "${TERMUXER}" = "screen" ]; then
		    local pid_server_screen=$(ps -o pid,command ax | grep -v grep | grep SCREEN | grep "${MCSERVERID} "  | awk '{ print $1 }') #Das Leerzeichen am Ende des letzten grep, damit lalas1 und lalas1-test unterschieden werden.
	  	else
		    local pid_server_screen=$(ps -o pid,command ax | grep -v grep | grep tmux | grep "${MCSERVERID} "  | awk '{ print $1 }') #Das Leerzeichen am Ende des letzten grep, damit lalas1 und lalas1-test unterschieden werden.
		fi
		if [ ! -z "$pid_server_screen" ]
		then
		    #We use one screen per server, get all processes with ppid of pid_server_screen
		    local pid_server=$(ps -o ppid,pid ax | awk '{ print $1,$2 }' | grep "^${pid_server_screen}" | cut -d' ' -f2) 
		    echo ${pid_server}
		fi
}

# After this function the server must be offline; if not you get serious problems :P
function mc_stop() {
        [ ${DODEBUG} -eq 1 ] && set -x
        if is_running
        then
		#Give the server some time to shutdown itself.
                echo "${JAR_FILE} is running... stopping."
		local _say=$(echo ${SAY_SERVER_STOP} | sed "s/###sec###/${WAITTIME_BEFORE_SHUTDOWN}/")
    		if [ "${TERMUXER}" = "screen" ]; then
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say ${_say}\"\015'"
                    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"save-all\"\015'"
		else
                    as_user "tmux send-keys -t ${MCSERVERID} 'say \"${_say}\"'"
  		    as_user "tmux send-keys -t ${MCSERVERID} C-m"
                    as_user "tmux send-keys -t ${MCSERVERID} 'save-all'"
                    as_user "tmux send-keys -t ${MCSERVERID} C-m"
		fi 
                #

		if [ ${PRINT_COUNTTOWN} = "true" ]; then
		    for i in $(seq 1 ${WAITTIME_BEFORE_SHUTDOWN});
		    do
			sleep 1
			let TIME_UNTIL="${WAITTIME_BEFORE_SHUTDOWN}-${i}"
			local _say=$(echo ${SAY_SERVER_STOP_COUNTDOWN} | sed "s/###sec###/${TIME_UNTIL}/")
    			if [ "${TERMUXER}" = "screen" ]; then
			    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"say ${_say}\"\015'"
			else
			    as_user "tmux send-keys -t ${MCSERVERID} 'say \"${_say}\"'" 
			    as_user "tmux send-keys -t ${MCSERVERID} C-m"
			fi
			    
		    done
		else
		    sleep ${WAITTIME_BEFORE_SHUTDOWN}
		fi

    		if [ "${TERMUXER}" = "screen" ]; then
		    as_user "screen -p 0 -S ${MCSERVERID} -X eval 'stuff \"stop\"\015'"
		else
		    as_user "tmux send-keys -t ${MCSERVERID} 'stop'"
		    as_user "tmux send-keys -t ${MCSERVERID} C-m"

		fi
	
                sleep ${WAIT_BEFORE_KILL}
        else
                echo "${JAR_FILE} was not running."
        fi

	local _count=0
 	while is_running #If the server is still running, kill it.
	do
                echo "${JAR_FILE} could not be shut down... still running."
		echo "Forcing server to stop ... kill :P ..."
		local pid_server=$(get_server_pid)
		echo "Killing pid $pid_server"
		as_user "kill -9 $pid_server"
		if [ $? ]
		then
			echo "Successfully killed ${JAR_FILE} (pid $pid_server)."
		else
			echo "Check that ... could not kill -9 $pid_server"
		fi

    		if [ "${TERMUXER}" = "screen" ]; then
		    #noch laufende Screen-Sitzungen beenden
		    as_user "screen -wipe"
		fi
		_count=$(($count+1))
		if [ $_count -ge 9 ]; then	#maximal 10 Versuche, den Server zu killen
			echo "Server could not be killed... after 10 tries..."
			break
		fi
        done
}

# If a server runs in a ramdisk, copy the content of SERVERDIR_PRERUN to SERVERDIR
function sync_to_ramdisk() {
#FIXME add check is FIXME is mounted before starting a server.
    [ ${DODEBUG} -eq 1 ] && set -x
    if is_ramdisk
    then
        if [ -z "$(ls -A ${SERVERDIR_PRERUN})" ];
        then
	    echo "Error, SERVERDIR_PRERUN(${SERVERDIR_PRERUN}) is empty, it sould NOT be."
	else
	    if is_running
	    then
	        echo "Server is running; stop it before syncing."
            else
	        as_user "rsync -a --delete \"${SERVERDIR_PRERUN}/\" \"${SERVERDIR}\""
            fi
	fi
    else
        echo "There is no ramdisk mounted in \"${SERVERDIR}\""
    fi
}

# If a server runs in a ramdisk, copy the content of SERVERDIR to SERVERDIR_PRERUN
function sync_from_ramdisk() {
    [ ${DODEBUG} -eq 1 ] && set -x
    if is_ramdisk
    then
        if [ -z "$(ls -A ${SERVERDIR})" ];
	then
	    echo "Error, SERVERDIR(${SERVERDIR}) is empty, it sould NOT be."
        else
	    if is_running
	    then
	        echo "Server is running; stop it before syncing."
	    else
	        as_user "rsync -a --delete \"${SERVERDIR}/\" \"${SERVERDIR_PRERUN}\""
	    fi
	fi
    else
    	echo "There is no ramdisk mounted in \"${SERVERDIR}\""
    fi
}

function mc_backup() {
   [ ${DODEBUG} -eq 1 ] && set -x
   [ -d "${BACKUPDIR}" ] || mkdir -p "${BACKUPDIR}"
   echo "Backing up ${MCSERVERID}."

#   if is_ramdisk
#   then
##        if 
#   	exit 1
#   fi

   if [ -z "$(ls -A ${SERVERDIR})" ];
   then
       echo -e "Warning...\nSomething must be wrong, SERVERDIR(\"${SERVERDIR}\") is empty.\nWon't do a backup."
       exit 1
   fi


   case ${BACKUPSYSTEM} in
        tar)
	   # Wir erstellen pro Tag ein Unterverzeichnis im Backupverzeichnis. Name ist das Datum. Falls dann quota voll ist, werden ja Verzeichnisse in der Hauptebene geloescht, also dann immer ganze Tagesbackups.
	   # Wenn fuer den aktuellen Tag noch kein Verzeichnis existiert, dann legen wir es an und machen ein initiales komplettes Backup.
	   # Existiert der Ordner bereits, dann koennen wir davon ausgehen, dass ein Komplettbackup existiert und auch eine snapshot datei und machen ein inkrementelles Backup.

	   # There is no quota-support for BACKUPSYSTEM=tar.

	   DATE=$(date "+%Y-%m-%d")
	   TIME=$(date "+%H-%M-%S")
	   THISBACKUP="${BACKUPDIR}/${DATE}" #Our current backup destiny.

	   [ -d "${THISBACKUP}" ] || mkdir -p "${THISBACKUP}" # Create daily directory if it does not exist.

	   TAR_SNAP_FILE="${THISBACKUP}/${SERVERNAME}.snap" #Snapshot file for tar, with meta information.
	   [ -f "${TAR_SNAP_FILE}" ] && BACKUP_TYPE="inc" || BACKUP_TYPE="full" #If DIR for today exists, do incremental, else full backup.

	   #Create backup tar.
	   TAR_FILE="${THISBACKUP}/${SERVERNAME}.${TIME}.${BACKUP_TYPE}.tar"
	   as_user "cd && ${RUNBACKUP_NICE} ${RUNBACKUP_IONICE} tar -cvf '${TAR_FILE}' --exclude='*.log' -g '${TAR_SNAP_FILE}' '${SERVERDIR}' > /dev/null 2>&1"
	  ;;
	rdiff)
	   local _excludes=""
	   for i in ${RDIFF_EXCLUDES[@]}
	   do
	      _excludes="$_excludes --exclude ${SERVERDIR}/$i"
	   done
	   ${RUNBACKUP_NICE} ${RUNBACKUP_IONICE} ${BIN_RDIFF} ${_excludes} "${SERVERDIR}" "${BACKUPDIR}/${SERVERNAME}-rdiff"

	   trim_to_quota ${BACKUP_QUOTA_MiB}	
	  ;;
   esac
}

function listbackups() {
    [ ${DODEBUG} -eq 1 ] && set -x
	if [ "${BACKUPSYSTEM}" != "rdiff" ]
	then
		echo "Error: listbackups is only available for usage with rdiff-backup; change BACKUPSYSTEM in \"$2\" or in user-settings-file in order to use rdiff-backup."
	else
		echo "Backups for server \"${SERVERNAME}\""
		${BIN_RDIFF} -l "${BACKUPDIR}/${SERVERNAME}-rdiff"
		${BIN_RDIFF} --list-increment-sizes "${BACKUPDIR}/${SERVERNAME}-rdiff"
	fi
}


# Returns output like "2 9", which means: ID:2, 9 times.
function lottery_rand() {
        [ ${DODEBUG} -eq 1 ] && set -x
	local _max_item_count=10
	local anzahl_items=$(wc -l ${ID_LIST} | cut -d' ' -f 1)

	local random_count=$((1+$RANDOM%$(($_max_item_count-1)))) #Anzahl der Items, 1 bis 10
	local random_line=$((1+$RANDOM%${anzahl_items}))
	local id_from_random_line=$(head -n ${random_line} ${ID_LIST} | tail -n1)

	echo $id_from_random_line ${random_count}
}

#Gives a named player the items from lottery_rand().
function lottery() {
    [ ${DODEBUG} -eq 1 ] && set -x
    local zeugs=$(lottery_rand)
    local give_id=$(echo $zeugs | cut -d' ' -f1)
    local give_count=$(echo $zeugs | cut -d' ' -f2)

    local name=$1
    
    #get name for our item
    #wir brauchen die ID ohne eventuelles :x
    local _cleared_give_id=$(echo ${give_id} | cut -d':' -f1)
    local name_for_id=$(grep "^${_cleared_give_id}:" "${ID_LIST_NAMES}" | cut -d':' -f2)
    
    sendcommand "say Gewinn fuer ${name}: ${give_count} ${name_for_id}($give_id)."
    sendcommand "give ${name} ${zeugs}"
    echo -en "Name: ${name}\nAnzahl: ${give_count}\nBezeichnung(ID): ${name_for_id}(${give_id})\nDone.\n"

}

function sendcommand() {
        [ ${DODEBUG} -eq 1 ] && set -x
	if is_running
        then
    		if [ "${TERMUXER}" = "screen" ]; then
		    as_user "screen -S $MCSERVERID -p 0 -X stuff '${1}'"
		    as_user "screen -S $MCSERVERID -p 0 -X stuff $(printf \\r)"
		else
		    as_user "tmux send-keys -t '$MCSERVERID' '${1}'"
		    as_user "tmux send-keys -t '$MCSERVERID' C-m"
		fi
	fi  
}


echo "$@" > /dev/null 2>&1 #$_ doesn't work without this :/ FIXME
if [ "$_" = '-debug' ]; #Show shell trace output...
then
    DODEBUG=1
else
    DODEBUG=0
fi
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
  lottery)
    lottery "${3}"
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
  s-to-ramd)
     sync_to_ramdisk
     ;;
  s-from-ramd)
     sync_from_ramdisk
     ;;
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
	sendcommand "${3}"
    ;;
  pid)
	get_server_pid
    ;;
  *)cat << EOHELP
Usage: ${0} SETTINGS_FILE COMMAND [ARGUMENT]

COMMANDS
    start                 Start the server.
    stop                  Stop the server.
    restart               Restart the server.
    backup                Backup the server.
    s-to-ramd		  Sync server contents from SERVERDIR_PRERUN("${SERVERDIR_PRERUN}") to SERVERDIR("${SERVERDIR}")
    s-from-ramd		  Sync server contents from SERVERDIR("${SERVERDIR}") to SERVERDIR_PRERUN("${SERVERDIR_PRERUN}")
    listbackups           List current incremental backups (only available for BACKUPSYSTEM="rdiff").
    status                Prints current status of the server (online/offline)
    sendcommand|sc|c      Send command to the server given as [ARGUMENT]
    lottery <playername>  Gives a player a random count of a random item. (Player must have a free inventory slot.)
    pid		          Get pid of a server process.
    -debug		  Must be the last argument. Enables shell trace output (set -x)

EXAMPLES
    Send a message to all players on the server:
    ${0} SETTINGS_FILE sendcommand "say We are watching you :P"

    Give me some golden apples:
    ${0} /etc/minecraft-server/userx/serverx sendcommand "give yourname 322 100"


EOHELP
    exit 1
  ;;
esac

exit 0

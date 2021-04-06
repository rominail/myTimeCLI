#!/bin/bash

SCRIPT_NAME=`basename "$0"`
SCRIPT_NAME_NO_EXT=${SCRIPT_NAME%\.*}
CONF_FILE="${SCRIPT_NAME_NO_EXT}.conf"
TMP_COOKIE_FILE="tmp_mytime_cookie.txt"
TMP_HTML_FILE="tmp_mytime_connected.html"
INIT_OPTION="--init"
EXEC_OPTION="-e"

typeset -A config # init array
config=( # set default values in config array
    [employeeId]=""
    [supervisorId]=""
    [bearer]=""
    [dayStart]="08:00"
    [dayEnd]="18:00"
    [breakStart]="12:00"
    [breakEnd]="13:00"
)

if [ ! -e $CONF_FILE ]
then
    if [ "$1" = $INIT_OPTION ]
    then
    	echo 'Please type your email'
    	read mytimeEmail
    	echo 'Please type your password'
    	read mytimePassword
    	
    	echo 'If you did non write correctly your credentials, delete the following file and try again $CONF_FILE'
    	echo 'Building the configuration file...'
    	
    	# Connection	
		curl 'https://www.mytime.fr/espace-client/connexion.php' \
		  -H 'Connection: keep-alive' \
		  -H 'Cache-Control: max-age=0' \
		  -H 'Upgrade-Insecure-Requests: 1' \
		  -H 'Origin: https://www.mytime.fr' \
		  -H 'Content-Type: application/x-www-form-urlencoded' \
		  -b $TMP_COOKIE_FILE -c $TMP_COOKIE_FILE \
		  --data-raw "login=$mytimeEmail&mdp=$mytimePassword&valider=" \
		  --compressed
		
		# Fetching homepage
		curl https://www.mytime.fr/controller/user/tableau_de_bord.php -b $TMP_COOKIE_FILE -c $TMP_COOKIE_FILE -s -L > $TMP_HTML_FILE

		# Grepping tokens
		config['bearer']=$(cat $TMP_HTML_FILE | grep Bearer | cut -d'"' -f4  | awk '{print $2}')
		config['supervisorId']=$(cat $TMP_HTML_FILE | grep supervisor_params | cut -d'/' -f2)
		config['employeeId']=$(cat $TMP_HTML_FILE | grep "var SESSION_USER_ID =" | cut -d'"' -f2)
		
		rm -f $TMP_COOKIE_FILE $TMP_HTML_FILE
    	
    	touch $CONF_FILE
    	for varname in "${!config[@]}"
		do
			echo "$varname=${config[$varname]}" >> $CONF_FILE
		done
    	echo "Config file $CONF_FILE has been generated"
    	echo "Edit it if needed"
    	exit 0
    else
		echo "Config file missing, please run script with $INIT_OPTION option : $SCRIPT_NAME $INIT_OPTION"
	exit 1
    fi
fi

# Fetching config
while read line
do
    if echo $line | grep -F = &>/dev/null
    then
        varname=$(echo "$line" | cut -d '=' -f 1)
        config[$varname]=$(echo "$line" | cut -d '=' -f 2-)
    fi
done < $CONF_FILE
# Config fetched

today=$(date +%Y-%m-%d)
dayStartString="$today ${config[dayStart]}:00"
dayEndString="$today ${config[dayEnd]}:00"
breakStartString="$today ${config[breakStart]}:00"
breakEndString="$today ${config[breakEnd]}:00"
nowString=$(date +%Y-%m-%d\ %H:%M:%S)

# Compute the seconds since epoch
dayStart=$(date --date="$dayStartString" +%s)
dayEnd=$(date --date="$dayEndString" +%s)
breakStart=$(date --date="$breakStartString" +%s)
breakEnd=$(date --date="$breakEndString" +%s)
now=$(date --date="$nowString" +%s)

deltaDayStart=$(expr $dayStart - $now)
deltaBreakStart=$(expr $breakStart - $now)
deltaBreakEnd=$(expr $breakEnd - $now)
deltaDayEnd=$(expr $dayEnd - $now)
if [ $deltaDayStart -lt 0 ]
then
	deltaDayStart=$(expr 0 - $deltaDayStart)
fi
if [ $deltaBreakStart -lt 0 ]
then
	deltaBreakStart=$(expr 0 - $deltaBreakStart)
fi
if [ $deltaBreakEnd -lt 0 ]
then
	deltaBreakEnd=$(expr 0 - $deltaBreakEnd)
fi
if [ $deltaDayEnd -lt 0 ]
then
	deltaDayEnd=$(expr 0 - $deltaDayEnd)
fi
event="DEBUT"
tmpDelta=$deltaDayStart
if [ $deltaBreakStart -lt $tmpDelta ]
then
	event="DEBUT_PAUSE"
	tmpDelta=$deltaBreakStart
fi
if [ $deltaBreakEnd -lt $tmpDelta ]
then
	event="FIN_PAUSE"
	tmpDelta=$deltaBreakEnd
fi
if [ $deltaDayEnd -lt $tmpDelta ]
then
	event="FIN"
	tmpDelta=$deltaDayEnd
fi

if [ "$1" = $EXEC_OPTION ]
then
	data=
	data+=$'------WebKitFormBoundaryUmWd8dBF9CFLa0dr\r\nContent-Disposition: form-data; name="supervisor_id"\r\n\r\n'
	data+=${config[supervisorId]}
	data+=$'\r\n------WebKitFormBoundaryUmWd8dBF9CFLa0dr\r\nContent-Disposition: form-data; name="employee_id"\r\n\r\n'
	data+=${config[employeeId]}
	data+=$'\r\n------WebKitFormBoundaryUmWd8dBF9CFLa0dr\r\nContent-Disposition: form-data; name="type_pointage"\r\n\r\n'
	data+=$event
	data+=$'\r\n'
	echo "Sending request"
	echo ""
	curl 'https://apibeta.mytime.fr/v2/clock_in/end' \
	-H "Authorization: Bearer ${config[bearer]}" \
	-H 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryUmWd8dBF9CFLa0dr' \
	-H 'User-Agent: Curl CLI https://github.com/rominail/myTimeCLI' \
	--data-binary "$data" \
	--compressed
	echo ""
	echo "Request sent"
	echo ""
	echo "$event;$nowString" >> "$SCRIPT_NAME_NO_EXT.log"
else
	echo "To execute pointage for $event specify $EXEC_OPTION : $SCRIPT_NAME $EXEC_OPTION"
fi

exit 0
 	 


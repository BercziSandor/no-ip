#!/bin/bash
set -e

usage() {
    echo "Usage:
    no-ip.sh -u=USERNAME -p=PASSWORD -h=host.sample.com -d=true -l=/path/to/logfile.log
        Parameters:
            -u, --username: Username to logon to no-ip.com.
            -p, --password: Password to logon to no-ip.com.
            -h, --hostname: The domain name to update.
            -d, --detectip: Tells the script to detect your external IP address. This takes precedence over -i.
            -i, --ip:		Maually sets the IP address to update. If neither -d or -i are specified, no-ip will use the IP address it detects.
            -n, --interval:	When running the script as a daemon/service (see Installation), this will update no-ip every n minutes.
            -l, --logfile:	Sets the path to a log file. This file must be writable.
            -c, --config:	Sets the path to a config file. This file must be readable. Config file parameters take precedence over command line parameters.
"
}

create_ini(){
    i="$SCRIPTDIR/no-ip.template.ini"
    [ -e "$i" ] && rm "$i"
    echo "user=" >> "$i"
    echo "password=" >> "$i"
    echo "logfile=" >> "$i"
    echo "hostname=" >> "$i"
    echo "detectip=" >> "$i"
    echo "ip=" >> "$i"
    echo "interval=" >> "$i"
}



ini() {
    USER=""
    PASSWORD=""
    HOSTNAME=""
    LOGFILE=""
    DETECTIP="true"
    IP=""
    RESULT=""
    INTERVAL=0
    CONFIG_FILE="$SCRIPTDIR/no-ip.ini"

    create_ini


    # DEFAULTS
    DETECTIP=true

    for i in "$@"; do
        case $i in
        -u=* | --user=*)
            USER="${i#*=}"
            ;;
        -p=* | --password=*)
            PASSWORD="${i#*=}"
            ;;
        -l=* | --logfile=*)
            LOGFILE="${i#*=}"
            ;;
        -h=* | --hostname=*)
            HOSTNAME="${i#*=}"
            ;;
        -d=* | --detectip=*)
            DETECTIP="${i#*=}"
            ;;
        -i=* | --ip=*)
            IP="${i#*=}"
            ;;
        -n=* | --interval=*)
            INTERVAL="${i#*=}"
            ;;
        -c=* | --config=*)
            CONFIG_FILE="${i#*=}"
            ;;
        *) ;;
        esac
    done

    if [ -n "$CONFIG_FILE" ]; then
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "Config file '$CONFIG_FILE' not found, aborting."
            exit 10
        fi
    elif [ -e "$SCRIPTDIR/no-ip.ini" ]; then
        CONFIG_FILE="$SCRIPTDIR/no-ip.ini"
    elif [ -e "/etc/no-ip/no-ip.ini" ]; then
        CONFIG_FILE="/etc/no-ip/no-ip.ini"
    else
        echo "Config file not found. Aborting."
        exit 11
    fi

    echo "Config file: [$CONFIG_FILE]"
    echo -n " reading..."
    while read line; do
        case $line in
        user=*)
            USER="${line#*=}"
            ;;
        password=*)
            PASSWORD="${line#*=}"
            ;;
        logfile=*)
            LOGFILE="${line#*=}"
            ;;
        hostname=*)
            HOSTNAME="${line#*=}"
            ;;
        detectip=*)
            DETECTIP="${line#*=}"
            ;;
        ip=*)
            IP="${line#*=}"
            ;;
        interval=*)
            INTERVAL="${line#*=}"
            ;;
        *) ;;

        esac
    done <"$CONFIG_FILE"
    echo " OK"

    echo -n " checking..."
    if [ -z "$USER" ]; then
        echo "No user was set. Use -u=username"
        exit 10
    fi

    if [ -z "$PASSWORD" ]; then
        echo "No password was set. Use -p=password"
        exit 20
    fi

    if [ -z "$HOSTNAME" ]; then
        echo "No host name. Use -h=host.example.com"
        exit 30
    fi

    if [ -n "$DETECTIP" ]; then
        IP=$(curl -s https://ipecho.net/plain)
    fi

    if [ -n "$DETECTIP" ] && [ -z $IP ]; then
        RESULT="Could not detect external IP."
    fi

    if [[ $INTERVAL != [0-9]* ]]; then
        echo "Interval is not an integer."
        exit 35
    fi
    echo " OK"

}

main() {
    if [ -n "$BASH_SOURCE" ]; then
        SCRIPTDIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
    elif [ -n "$ZSH_NAME" ]; then
        SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
    else
        echo "Not bash, not zsh. What else? Aborting. - Contact developer."
        exit 35
    fi
    ini $*

    USERAGENT="--user-agent=\"no-ip shell script/1.0 mail@mail.com\""
    BASE64AUTH=$(echo '"$USER:$PASSWORD"' | base64)
    AUTHHEADER="--header=\"Authorization: $BASE64AUTH\""
    NOIPURL="https://$USER:$PASSWORD@dynupdate.no-ip.com/nic/update"

    if [ -n "$IP" ] || [ -n "$HOSTNAME" ]; then
        NOIPURL="$NOIPURL?"
    fi

    if [ -n "$HOSTNAME" ]; then
        NOIPURL="${NOIPURL}hostname=${HOSTNAME}"
    fi

    if [ -n "$IP" ]; then
        if [ -n "$HOSTNAME" ]; then
            NOIPURL="$NOIPURL&"
        fi
        NOIPURL="${NOIPURL}myip=$IP"
    fi

    while :; do
        echo "Calling :'wget -qO- $AUTHHEADER $USERAGENT $NOIPURL'"
        echo "curl --user $USER:$PASSWORD $NOIPURL"
        # RESULT=$(wget -qO- $AUTHHEADER $USERAGENT $NOIPURL)

        if [ -z "$RESULT" ] && [ $? -ne 0 ]; then
            echo "Problem updating NO-IP."
            case $? in
            1)
                RESULT="General Error."
                ;;
            2)
                RESULT="General Error."
                ;;
            3)
                RESULT="File I/O Error"
                ;;
            4)
                RESULT="Network Failure"
                ;;
            5)
                RESULT="SSL Verfication Error"
                ;;
            6)
                RESULT="Authentication Failure"
                ;;
            7)
                RESULT="Protocol Error"
                ;;
            8)
                RESULT="Server issued an error response"
                ;;
            esac
        fi

        if [ -n "$LOGFILE" ]; then
            if [ ! -f "$LOGFILE" ]; then
                touch "$LOGFILE"
            fi
            DATE=$(date)
            echo "$DATE --  $RESULT" >>"$LOGFILE"
        fi

        if [ $INTERVAL -eq 0 ]; then
            break
        else
            sleep "${INTERVAL}m"
        fi

    done

}

main "$@"
exit 0

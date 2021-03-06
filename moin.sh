#!/usr/bin/env bash
#===============================================================================
#          FILE: moin.sh
#
#         USAGE: ./moin.sh
#
#   DESCRIPTION: Entrypoint for moinmoin docker container
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: David Personette (dperson@gmail.com),
#  ORGANIZATION:
#       CREATED: 2014-10-16 02:56
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error

### prefix: Configure expected URI location for service
# Arguments:
#   prefix) URI
# Return: setup URI
prefix() { local prefix="$1" file=/usr/local/share/moin/wikiconfig.py
    sed -i '/url_prefix_static = /s|'"'.*'"'|'"'$prefix'"'|' $file
}

### super: Configure admin user for wiki
# Arguments:
#   super) admin ID
# Return: setup admin ID
super() { local super="$1" file=/usr/local/share/moin/wikiconfig.py
    sed -i '/superuser/s|".*"|"'"$super"'"|' $file
}

### timezone: Set the timezone for the container
# Arguments:
#   timezone) for example EST5EDT
# Return: the correct zoneinfo file will be symlinked into place
timezone() { local timezone="${1:-EST5EDT}"
    [[ -e /usr/share/zoneinfo/$timezone ]] || {
        echo "ERROR: invalid timezone specified: $timezone" >&2
        return
    }

    if [[ -w /etc/timezone && $(cat /etc/timezone) != $timezone ]]; then
        echo "$timezone" >/etc/timezone
        ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
        dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1
    fi
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC=${1:-0}
    echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
    -h          This help
    -p \"</prefix>\" Configure URI prefix for wiki, if you want other than
                /wiki required arg: \"</prefix>\" - URI location
    -s \"<super>\" Configure superuser (admin ID) for the wiki
                required arg: \"<UserName>\" - The user to manage the wiki
    -t \"\"       Configure timezone (defaults to EST5EDT)
                possible arg: \"[timezone]\" - zoneinfo timezone for container

The 'command' (if provided and valid) will be run instead of moinmoin
" >&2
    exit $RC
}

while getopts ":hp:s:t:" opt; do
    case "$opt" in
        h) usage ;;
        p) prefix "$OPTARG" ;;
        s) super "$OPTARG" ;;
        t) timezone "$OPTARG" ;;
        "?") echo "Unknown option: -$OPTARG"; usage 1 ;;
        ":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ "${PREFIX:-""}" ]] && prefix "$PREFIX"
[[ "${SUPER:-""}" ]] && super "$SUPER"
[[ "${TZ:-""}" ]] && timezone "$TZ"
[[ "${USERID:-""}" =~ ^[0-9]+$ ]] && usermod -u $USERID -o www-data
[[ "${GROUPID:-""}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o www-data

chown -Rh www-data. /usr/local/share/moin/data /usr/local/share/moin/underlay \
            2>&1 | grep -iv 'Read-only' || :

if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
    exec "$@"
elif [[ $# -ge 1 ]]; then
    echo "ERROR: command not found: $1"
    exit 13
elif ps -ef | egrep -v grep | grep -q uwsgi; then
    echo "Service already running, please restart container to apply changes"
else
    [[ "${LANG:-""}" ]] || export LANG=en_US.UTF-8
    exec uwsgi --uid www-data \
                -s /tmp/uwsgi.sock \
                --uwsgi-socket 0.0.0.0:3031 \
                --plugins python \
                --pidfile /tmp/uwsgi-moinmoin.pid \
                --chdir /usr/local/share/moin \
                --python-path /usr/local/share/moin \
                --wsgi-file server/moin.wsgi \
                --master \
                --processes 4 \
                --harakiri 30 \
                --die-on-term \
                --thunder-lock
fi
#!/bin/sh
: > /dev/watchdog

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
command -v plymouth > /dev/null 2>&1 && plymouth --quit
exec > /dev/console 2>&1

systemctl --failed --no-legend --no-pager > /run/failed

ismounted() {
    findmnt "$1" > /dev/null 2>&1
}

if ! ismounted /usr; then
    echo "**************************FAILED**************************"
    echo "/usr not mounted!!"
    cat /proc/mounts >> /run/failed
    echo "**************************FAILED**************************"
fi

. /sbin/test-init.sh

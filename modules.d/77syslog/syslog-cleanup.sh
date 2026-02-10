#!/bin/sh

# Just cleans up a previously started syslogd

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if [ -f /tmp/syslog.server ]; then
    read -r syslogtype < /tmp/syslog.type
    if command -v "${syslogtype}-stop" > /dev/null; then
        "${syslogtype}"-stop
    else
        warn "syslog-cleanup: Could not find script to stop syslog of type \"$syslogtype\". Syslog will not be stopped."
    fi
fi

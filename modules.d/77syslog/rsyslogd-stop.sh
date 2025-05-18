#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

# Kills rsyslogd

if [ -f /var/run/syslogd.pid ]; then
    read -r pid < /var/run/syslogd.pid
    kill "$pid"
    kill -0 "$pid" && kill -9 "$pid"
else
    warn "rsyslogd-stop: Could not find a pid for rsyslogd. Won't kill it."
fi

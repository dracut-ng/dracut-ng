#!/bin/sh
: > /dev/watchdog
exec > /dev/console 2>&1

/usr/bin/systemctl --failed --no-legend --no-pager > /run/failed

. /sbin/test-init.sh

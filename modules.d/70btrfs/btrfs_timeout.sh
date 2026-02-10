#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

info "Scanning for all btrfs devices"
/sbin/btrfs device scan > /dev/null 2>&1

#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

for md in /dev/md[0-9_]*; do
    [ -b "$md" ] || continue
    need_shutdown
    break
done

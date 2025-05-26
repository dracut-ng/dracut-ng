#!/bin/sh

command -v getargs > /dev/null || . /lib/dracut-lib.sh

for modlist in $(getargs rd.driver.post); do
    (
        IFS=,
        for m in $modlist; do
            modprobe "$m"
        done
    )
done

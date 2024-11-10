#!/bin/sh

type getargs > /dev/null 2>&1 || . /lib/dracut-lib.sh

for modlist in $(getargs rd.driver.post); do
    (
        IFS=,
        for m in $modlist; do
            modprobe "$m"
        done
    )
done

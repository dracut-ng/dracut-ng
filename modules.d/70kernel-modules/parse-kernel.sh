#!/bin/sh

_modprobe_d=/run/modprobe.d
if [ ! -d $_modprobe_d ]; then
    mkdir -p $_modprobe_d
fi

for i in $(getargs rd.driver.pre); do
    (
        IFS=,
        for p in $i; do
            modprobe "$p" 2>&1 | vinfo
        done
    )
done

for i in $(getargs rd.driver.blacklist); do
    (
        IFS=,
        for p in $i; do
            echo "blacklist $p" >> $_modprobe_d/initramfsblacklist.conf
        done
    )
done

for p in $(getargs rd.driver.post); do
    echo "blacklist $p" >> $_modprobe_d/initramfsblacklist.conf
    _do_insmodpost=1
done

[ -n "$_do_insmodpost" ] && /sbin/initqueue --settled --unique --onetime insmodpost.sh
unset _do_insmodpost _modprobe_d

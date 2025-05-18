#!/bin/sh
export DRACUT_SYSTEMD=1
if [ -f /dracut-state.sh ]; then
    . /dracut-state.sh 2> /dev/null
fi
command -v getarg > /dev/null || . /lib/dracut-lib.sh

source_conf /etc/conf.d

make_trace_mem "hook pre-udev" '1:shortmem' '2+:mem' '3+:slab'
# pre pivot scripts are sourced just before we doing cleanup and switch over
# to the new root.
getargs 'rd.break=pre-udev' && emergency_shell -n pre-udev "Break before pre-udev"
source_hook pre-udev

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
unset i

export -p > /dracut-state.sh
exit 0

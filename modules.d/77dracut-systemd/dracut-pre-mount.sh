#!/bin/sh

export DRACUT_SYSTEMD=1
if [ -f /dracut-state.sh ]; then
    . /dracut-state.sh 2> /dev/null
fi
command -v getarg > /dev/null || . /lib/dracut-lib.sh

source_conf /etc/conf.d

make_trace_mem "hook pre-mount" '1:shortmem' '2+:mem' '3+:slab'
# Pre-pivot scripts are sourced just before cleanup and switching to the
# new root.
getargs 'rd.break=pre-mount' && emergency_shell -n pre-mount "Break before pre-mount"
source_hook pre-mount

export -p > /dracut-state.sh

exit 0

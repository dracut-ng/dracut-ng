#!/bin/bash

type info > /dev/null 2>&1 || . /lib/dracut-lib.sh

if [[ "$(ls -A /var/lib/systemd/coredump 2> /dev/null)" ]]; then

    mount -o remount,rw /sysroot

    for i in /var/lib/systemd/coredump/*; do
        [[ -f $i ]] || continue
        if [[ ! -f "/sysroot$i" ]]; then
            info "Copying $i to /sysroot"
            cp -f "$i" "/sysroot/var/lib/systemd/coredump"
        fi
    done
fi

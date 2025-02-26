#!/bin/bash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
NEWROOT=${NEWROOT:-'/sysroot'}

if getargbool 0 create_root.overlay; then
    mount -o remount,rw "$NEWROOT"
    mkdir -p /run/usr
    mount --make-private "$NEWROOT"
    mount --move "$NEWROOT"/usr/ /run/usr
    mount -t overlay overlay -o lowerdir=/run/usr,upperdir="$NEWROOT"/.overlay/usr/upper,workdir="$NEWROOT"/.overlay/usr/work "$NEWROOT"/usr
    chmod 755 "$NEWROOT"/usr
fi

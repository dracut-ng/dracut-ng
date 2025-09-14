#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getargbool 0 rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.live.overlay.readonly && readonly_overlay="--readonly" || readonly_overlay=""
getargbool 0 rd.overlay.auto && auto_overlay="yes" && overlayfs="yes"

if [ -n "$overlayfs" ]; then
    OPT=
    FS=

    boot_dev=$(findmnt --mountpoint "$NEWROOT" -o OPTIONS,FSTYPE -n)

    while IFS= read -r OPT FS; do
        printf '%s\n' "Processing: $OPT $FS"
    done < "$boot_dev"

    if [ -n "$auto_overlay" ] && [ "$FS" = "btrfs" ] && [ "$(btrfs property get "${NEWROOT}" ro)" = "ro=true" ]; then
        return 0
    fi

    if [ -n "$auto_overlay" ] && [ "$OPT" = "rw" ]; then
        return 0
    fi

    if [ -n "$readonly_overlay" ] && [ -h /run/overlayfs-r ]; then
        ovlfs=lowerdir=/run/overlayfs-r:/run/rootfsbase
    else
        ovlfs=lowerdir=/run/rootfsbase
    fi

    if ! strstr "$(cat /proc/mounts)" LiveOS_rootfs; then
        mount -t overlay LiveOS_rootfs -o "$ovlfs",upperdir=/run/overlayfs,workdir=/run/ovlwork "$NEWROOT"
    fi
fi

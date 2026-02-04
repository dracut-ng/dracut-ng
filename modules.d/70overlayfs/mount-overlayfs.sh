#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh
command -v get_rd_overlay > /dev/null || . /lib/overlayfs-lib.sh

getargbool 0 rd.overlay -d rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.overlay.readonly -d rd.live.overlayfs.readonly && readonly_overlay="--readonly" || readonly_overlay=""
overlay=$(get_rd_overlay)

[ -n "$overlayfs" ] || [ -n "$overlay" ] || return 0

# Only proceed if prepare-overlayfs.sh has run and set up rootfsbase.
# This handles the case where root isn't available yet (e.g., network root like NFS).
# The script will be called again at pre-pivot when the root is mounted.
[ -e /run/rootfsbase ] || return 0

if [ -n "$readonly_overlay" ] && [ -h /run/overlayfs-r ]; then
    ovlfs=lowerdir=/run/overlayfs-r:/run/rootfsbase
else
    ovlfs=lowerdir=/run/rootfsbase
fi

if ! strstr "$(cat /proc/mounts)" LiveOS_rootfs; then
    mount -t overlay LiveOS_rootfs -o "$ovlfs",upperdir=/run/overlayfs,workdir=/run/ovlwork "$NEWROOT"
fi

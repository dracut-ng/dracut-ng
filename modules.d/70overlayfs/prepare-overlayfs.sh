#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getargbool 0 rd.overlayfs -d rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.overlay.reset -d rd.live.overlay.reset && reset_overlay="yes"

[ -n "$overlayfs" ] || return 0

if ! [ -e /run/rootfsbase ]; then
    mkdir -m 0755 -p /run/rootfsbase
    mount --bind "$NEWROOT" /run/rootfsbase
fi

mkdir -m 0755 -p /run/overlayfs
mkdir -m 0755 -p /run/ovlwork
if [ -n "$reset_overlay" ] && [ -h /run/overlayfs ]; then
    ovlfsdir=$(readlink /run/overlayfs)
    info "Resetting the OverlayFS overlay directory."
    rm -r -- "${ovlfsdir:?}"/* "${ovlfsdir:?}"/.* > /dev/null 2>&1
fi

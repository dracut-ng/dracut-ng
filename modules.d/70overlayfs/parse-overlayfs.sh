#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

overlayroot=$(getarg overlayroot=)
overlay=$(getarg rd.overlay -d rd.live.overlay)

# Make overlayroot= an alias for rd.overlay=
root=$(getarg root=)
if [ "${root%%:*}" = "live" ] || getargbool 0 rd.live.image; then
    if [ -n "$overlayroot" ] && [ -z "$overlay" ]; then
        echo "rd.overlay=$overlayroot" >> /etc/cmdline.d/80-overlayfs.conf
    fi
fi

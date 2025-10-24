#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

copymods=$(getarg rd.driver.copy=)

if [ -n "$copymods" ]; then
    KVERSION="$(uname -r)"

    if [ ! -d "/lib/modules/$KVERSION" ]; then
        warn "Something odd, no /lib/modules/$KVERSION in initramfs."
        exit 0
    fi

    [ -d "$NEWROOT/lib/modules" ] || mkdir -p "$NEWROOT/lib/modules" \
        || {
            warn "No /lib/modules in target. cannot help."
            exit 0
        }

    if [ -d "$NEWROOT/lib/modules/$KVERSION" ]; then
        if [ "${copymods#*force}" = "$copymods" ]; then
            exit 0
        else
            warn "copying over existing modules! due to rd.driver.copy=force"
        fi
    fi

    mount -t tmpfs copymods "$NEWROOT/lib/modules" \
        || {
            warn "failed mount of tmpfs"
            exit 0
        }

    cp -a "/lib/modules/$KVERSION" "$NEWROOT/lib/modules" \
        || {
            warn "failed to copy modules to target root"
            exit 0
        }
fi

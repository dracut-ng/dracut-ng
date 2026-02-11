#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if ! getargbool 0 rd.driver.export; then
    return 0
fi

driver_export=$(getarg rd.driver.export=)

KVERSION="$(uname -r)"

if [ ! -d "/lib/modules/$KVERSION" ]; then
    warn "Something odd, no /lib/modules/$KVERSION in initramfs."
    return 0
fi

[ -d "$NEWROOT/lib/modules" ] || mkdir -p "$NEWROOT/lib/modules" \
    || {
        warn "No /lib/modules in target. cannot help."
        return 0
    }

if [ -d "$NEWROOT/lib/modules/$KVERSION" ]; then
    if [ "${driver_export#*force}" = "$driver_export" ]; then
        warn "/lib/modules/$KVERSION exists. To export modules set rd.driver.export=force!"
        return 0
    else
        info "Due to rd.driver.export=force exporting over existing modules!"
    fi
fi

mount -t tmpfs driver_export "$NEWROOT/lib/modules" \
    || {
        warn "Failed mount of tmpfs."
        return 0
    }

cp -a "/lib/modules/$KVERSION" "$NEWROOT/lib/modules" \
    || {
        warn "Failed to export modules to target root."
        return 0
    }

#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

setup_overlay_genrules() {
    local overlay_param="$1"
    local root
    local overlayLabel

    [ "${overlay_param#LABEL=}" = "$overlay_param" ] && return

    root=$(getarg root=)
    [ "${root%%:*}" != "live" ] && ! getargbool 0 rd.live.image && return

    overlayLabel=${overlay_param#LABEL=}
    [ -b "/dev/disk/by-label/${overlayLabel}" ] && return

    [ "${root#live:/dev/}" = "$root" ] && return

    printf 'SYMLINK=="%s", RUN+="/sbin/initqueue --settled --onetime --unique /sbin/create-overlay %s"\n' \
        "${root#live:/dev/}" "${root#live:}" >> /etc/udev/rules.d/95-create-overlay.rules
    wait_for_dev -n "${root#live:}"
}

overlayroot=$(getarg overlayroot=)
overlay=$(getarg rd.overlay -d rd.live.overlay)

overlay_param="${overlay:-$overlayroot}"

[ -n "$overlay_param" ] && setup_overlay_genrules "$overlay_param"

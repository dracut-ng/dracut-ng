#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

overlayroot=$(getarg overlayroot=)
overlay=$(getarg rd.overlay -d rd.live.overlay)

overlay_param="${overlay:-$overlayroot}"

if [ -n "$overlay_param" ]; then
    case "$overlay_param" in
        LABEL=*)
            root=$(getarg root=)
            if [ "${root%%:*}" = "live" ] || getargbool 0 rd.live.image; then
                overlayLabel=${overlay_param#LABEL=}
                if [ ! -b "/dev/disk/by-label/${overlayLabel}" ]; then
                    case "$root" in
                        live:/dev/*)
                            printf 'SYMLINK=="%s", RUN+="/sbin/initqueue --settled --onetime --unique /sbin/create-overlay %s"\n' \
                                "${root#live:/dev/}" "${root#live:}" >> /etc/udev/rules.d/95-create-overlay.rules
                            wait_for_dev -n "${root#live:}"
                            ;;
                    esac
                fi
            fi
            ;;
    esac
fi

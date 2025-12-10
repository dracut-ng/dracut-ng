#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getargbool 0 rd.overlayfs -d rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.live.overlay.reset && reset_overlay="yes"

overlayroot=$(getarg overlayroot=)

overlay_mode="tmpfs"
overlay_device=""

if [ -n "$overlayroot" ]; then
    overlayfs="yes"

    case "$overlayroot" in
        tmpfs*)
            overlay_mode="tmpfs"
            ;;
        /dev/* | LABEL=* | UUID=* | PARTLABEL=* | PARTUUID=*)
            overlay_mode="device"
            overlay_device=$(label_uuid_to_dev "$overlayroot")
            if [ -z "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlayroot', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        device:*)
            overlay_mode="device"
            overlay_device="${overlayroot#device:}"
            overlay_device="${overlay_device#dev=}"
            overlay_device=$(label_uuid_to_dev "$overlay_device")
            if [ -z "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlayroot', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        disabled)
            overlayfs=""
            ;;
        *)
            warn "Unknown overlayroot format '$overlayroot', using tmpfs"
            overlay_mode="tmpfs"
            ;;
    esac
fi

if [ -n "$overlayfs" ]; then
    if ! [ -e /run/rootfsbase ]; then
        mkdir -m 0755 -p /run/rootfsbase
        mount --bind "$NEWROOT" /run/rootfsbase
    fi

    if [ "$overlay_mode" = "device" ] && [ -n "$overlay_device" ]; then
        info "Attempting to use persistent overlay on $overlay_device"

        wait_for_dev -n "$overlay_device"

        mkdir -m 0755 -p /run/overlayfs-backing

        if mount "$overlay_device" /run/overlayfs-backing; then
            info "Successfully mounted persistent overlay on $overlay_device"

            mkdir -m 0755 -p /run/overlayfs-backing/overlay
            mkdir -m 0755 -p /run/overlayfs-backing/ovlwork

            ln -sf /run/overlayfs-backing/overlay /run/overlayfs
            ln -sf /run/overlayfs-backing/ovlwork /run/ovlwork

            if [ -n "$reset_overlay" ]; then
                info "Resetting persistent overlay."
                rm -rf /run/overlayfs-backing/overlay/* /run/overlayfs-backing/overlay/.[!.]* 2> /dev/null
                rm -rf /run/overlayfs-backing/ovlwork/* /run/overlayfs-backing/ovlwork/.[!.]* 2> /dev/null
            fi
        else
            warn "Failed to mount $overlay_device, falling back to tmpfs"
            overlay_mode="tmpfs"
        fi
    fi

    # Tmpfs mode (default or fallback)
    if [ "$overlay_mode" = "tmpfs" ]; then
        info "Using tmpfs overlay (changes will not persist across reboots)"

        mkdir -m 0755 -p /run/overlayfs
        mkdir -m 0755 -p /run/ovlwork
        if [ -n "$reset_overlay" ]; then
            ovlfsdir=$(readlink /run/overlayfs) || ovlfsdir="/run/overlayfs"
            info "Resetting the OverlayFS overlay directory."
            rm -r -- "${ovlfsdir:?}"/* "${ovlfsdir:?}"/.* > /dev/null 2>&1
        fi
    fi
fi

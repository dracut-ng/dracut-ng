#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getargbool 0 rd.overlayfs -d rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.live.overlay.reset && reset_overlay="yes"

overlayroot=$(getarg overlayroot=)

root=$(getarg root=)
liveroot=$(getarg liveroot=)
if [ "${root%%:*}" = "live" ] || [ "${liveroot%%:*}" = "live" ] || getargbool 0 rd.live.image; then
    case "$overlayroot" in
        tmpfs | tmpfs:*)
            info "Live boot with tmpfs overlay requested"
            ;;
        "")
            info "Live boot with tmpfs overlay (rd.overlayfs=1)"
            ;;
        *)
            info "Live boot detected, skipping device overlay setup (use rd.live.overlay for persistent overlays)"
            return 0
            ;;
    esac
fi

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
            if [ ! -b "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlayroot', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        device:*)
            overlay_mode="device"
            overlay_device="${overlayroot#device:}"
            overlay_device="${overlay_device#dev=}"
            overlay_device=$(label_uuid_to_dev "$overlay_device")
            if [ ! -b "$overlay_device" ]; then
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
        else
            warn "Failed to mount $overlay_device, falling back to tmpfs"
            overlay_mode="tmpfs"
        fi
    fi

    # Tmpfs mode (default or fallback)
    if [ "$overlay_mode" = "tmpfs" ]; then
        info "Using tmpfs overlay (changes will not persist across reboots)"

        [ -h /run/overlayfs ] || {
            mkdir -m 0755 -p /run/overlayfs
            mkdir -m 0755 -p /run/ovlwork
        }
    fi

    # Only applies to persistent overlays
    if [ -n "$reset_overlay" ] && [ -h /run/overlayfs ]; then
        ovlfsdir=$(readlink /run/overlayfs)
        info "Resetting the OverlayFS overlay directory."
        rm -r -- "${ovlfsdir:?}" > /dev/kmsg 2>&1
        mkdir -p "$ovlfsdir"
    fi
fi

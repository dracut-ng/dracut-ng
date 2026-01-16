#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getargbool 0 rd.overlayfs -d rd.live.overlay.overlayfs && overlayfs="yes"
getargbool 0 rd.overlay.reset -d rd.live.overlay.reset && reset_overlay="yes"

overlay=$(getarg rd.overlay -d rd.live.overlay)
overlayroot=$(getarg overlayroot=)

overlay_mode="tmpfs"
overlay_device=""

# Handle overlayroot parameter (cloud-initramfs-tools compatibility)
if getarg overlayroot= > /dev/null || getarg overlayroot > /dev/null; then
    # If overlayroot is set but empty, treat as overlayroot=1 (tmpfs mode)
    [ -z "$overlayroot" ] && overlayroot="1"

    case "$overlayroot" in
        1 | tmpfs | tmpfs*)
            overlayfs="yes"
            overlay_mode="tmpfs"
            ;;
        /dev/* | LABEL=* | UUID=* | PARTLABEL=* | PARTUUID=*)
            overlayfs="yes"
            overlay_mode="device"
            overlay_device=$(label_uuid_to_dev "$overlayroot")
            if [ ! -b "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlayroot', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        device:*)
            overlayfs="yes"
            overlay_mode="device"
            overlay_device="${overlayroot#device:}"
            overlay_device="${overlay_device#dev=}"
            overlay_device=$(label_uuid_to_dev "$overlay_device")
            if [ ! -b "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlayroot', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        0 | disabled)
            overlayfs=""
            ;;
        *)
            warn "Unknown overlayroot format '$overlayroot', using tmpfs"
            overlayfs="yes"
            overlay_mode="tmpfs"
            ;;
    esac
elif [ -n "$overlay" ]; then
    overlayfs="yes"

    case "$overlay" in
        LABEL=* | UUID=* | PARTLABEL=* | PARTUUID=* | /dev/*)
            overlay_mode="device"
            overlay_device=$(label_uuid_to_dev "$overlay")
            if [ ! -b "$overlay_device" ]; then
                warn "Failed to resolve device from '$overlay', falling back to tmpfs"
                overlay_mode="tmpfs"
            fi
            ;;
        *)
            # For dmsquash-live compatibility, any other format uses tmpfs
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

    if [ "$overlay_mode" = "tmpfs" ]; then
        info "Using tmpfs overlay (changes will not persist across reboots)"

        [ -h /run/overlayfs ] || {
            mkdir -m 0755 -p /run/overlayfs
            mkdir -m 0755 -p /run/ovlwork
        }
    fi

    if [ -n "$reset_overlay" ] && [ -h /run/overlayfs ]; then
        ovlfsdir=$(readlink /run/overlayfs)
        info "Resetting the OverlayFS overlay directory."
        rm -r -- "${ovlfsdir:?}" > /dev/kmsg 2>&1
        mkdir -p "$ovlfsdir"
    fi
fi

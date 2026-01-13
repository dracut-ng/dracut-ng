#!/bin/sh
# shellcheck disable=SC1091
. /lib/dracut-lib.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/console 2>&1

echo "Overlayfs test: verifying overlay is mounted and working"

if ! grep -q "LiveOS_rootfs" /proc/mounts; then
    echo "FAIL: overlayfs not found in /proc/mounts"
    echo "FAIL-NO-OVERLAY" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    poweroff -f
    exit 1
fi

echo "SUCCESS: overlayfs mounted"

if ! touch /test-overlay-write 2> /dev/null; then
    echo "FAIL: overlay is not writable"
    echo "FAIL-NOT-WRITABLE" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    poweroff -f
    exit 1
fi

echo "SUCCESS: overlay is writable"

if
    grep -q "overlayroot=LABEL=" /proc/cmdline || grep -q "overlayroot=UUID="
    /proc/cmdline
then
    echo "Testing persistent device overlay..."

    if ! grep -q "/run/overlayfs-backing" /proc/mounts; then
        if grep -q "overlayroot=LABEL=NONEXISTENT" /proc/cmdline; then
            echo "SUCCESS: non-existent device correctly fell back to tmpfs"
        else
            echo "FAIL: persistent overlay device not mounted at /run/overlayfs-backing"
            echo "FAIL-NO-BACKING" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
            poweroff -f
            exit 1
        fi
    else
        echo "SUCCESS: persistent overlay device mounted"

        if [ ! -L /run/overlayfs ]; then
            echo "FAIL: /run/overlayfs is not a symlink"
            echo "FAIL-NOT-SYMLINK" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
            poweroff -f
            exit 1
        fi

        overlay_target=$(readlink /run/overlayfs)
        if [ "$overlay_target" != "/run/overlayfs-backing/overlay" ]; then
            echo "FAIL: /run/overlayfs points to wrong target: $overlay_target"
            echo "FAIL-WRONG-SYMLINK" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
            poweroff -f
            exit 1
        fi

        echo "SUCCESS: /run/overlayfs correctly symlinked to persistent storage"
    fi
elif
    grep -q "rd.overlayfs=1" /proc/cmdline || grep -q "overlayroot=tmpfs"
    /proc/cmdline
then
    echo "Testing tmpfs overlay..."

    if [ -L /run/overlayfs ]; then
        echo "WARNING: /run/overlayfs is a symlink in tmpfs mode (might be fallback
from failed device mount)"
    else
        echo "SUCCESS: /run/overlayfs is a directory (tmpfs mode)"
    fi
fi

echo "=== Mount information ==="
grep -E "overlay|/run" /proc/mounts

echo "dracut-root-block-success" | dd oflag=direct,sync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none

echo "All overlayfs tests passed! Powering down."

sync

if [ -d /usr/lib/systemd/system ]; then
    systemctl poweroff
else
    poweroff -f
fi

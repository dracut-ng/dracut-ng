#!/bin/sh

# required binaries: cat dd grep mkdir mount sync

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# shellcheck disable=SC2317,SC2329  # called via EXIT trap
_poweroff() {
    local exit_code="$?"

    [ "$exit_code" -eq 0 ] || echo "Error: $0 failed with exit code $exit_code."
    echo "Powering down."

    if [ -d /usr/lib/systemd/system ]; then
        # graceful poweroff
        systemctl start poweroff.target --job-mode=replace-irreversibly --no-block
    else
        # force immediate poweroff
        poweroff -f
    fi
}

trap _poweroff EXIT

[ -e /proc/self/mounts ] \
    || (mkdir -p /proc && mount -t proc -o nosuid,noexec,nodev proc /proc)

grep -q '^sysfs /sys sysfs' /proc/self/mounts \
    || (mkdir -p /sys && mount -t sysfs -o nosuid,noexec,nodev sysfs /sys)

grep -q '^devtmpfs /dev devtmpfs' /proc/self/mounts \
    || (mkdir -p /dev && mount -t devtmpfs -o mode=755,noexec,nosuid,strictatime devtmpfs /dev)

grep -q '^tmpfs /run tmpfs' /proc/self/mounts \
    || (mkdir -p /run && mount -t tmpfs -o mode=755,noexec,nosuid,strictatime tmpfs /run)

: > /dev/watchdog

exec > /dev/console 2>&1
echo "made it to the test rootfs!"

if command -v systemctl > /dev/null 2>&1; then
    systemctl --failed --no-legend --no-pager >> /run/failed
fi

# run the test case specific test assertion if exists
if [ -x "/assertion.sh" ]; then
    echo "executing /assertion.sh"
    /assertion.sh
fi

if [ -s /run/failed ]; then
    echo "**************************FAILED**************************"
    cat /run/failed
    echo "**************************FAILED**************************"
else
    echo "dracut-root-block-success" | dd oflag=direct status=none of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
    sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
    echo "All OK"
fi

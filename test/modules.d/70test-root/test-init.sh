#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

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
    . /assertion.sh
fi

if [ -s /run/failed ]; then
    echo "**************************FAILED**************************"
    cat /run/failed
    echo "**************************FAILED**************************"
else
    echo "dracut-root-block-success" | dd oflag=direct,dsync status=none of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
    echo "All OK"
fi

echo "Powering down."

if [ -d /usr/lib/systemd/system ]; then
    # graceful poweroff
    systemctl poweroff
else
    # force immediate poweroff
    poweroff -f
fi

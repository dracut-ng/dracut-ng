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

if [ -s /failed ]; then
    echo "**************************FAILED**************************"
    cat /failed
    echo "**************************FAILED**************************"
else
    echo "dracut-root-block-success" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
    echo "All OK"
fi

export TERM=linux
export PS1='initramfs-test:\w\$ '
[ -f /etc/mtab ] || ln -sfn /proc/mounts /etc/mtab
[ -f /etc/fstab ] || ln -sfn /proc/mounts /etc/fstab
stty sane
echo "made it to the rootfs!"

. /lib/dracut-lib.sh

if getargbool 0 rd.shell; then
    strstr "$(setsid --help)" "control" && CTTY="-c"
    # shellcheck disable=SC2086
    setsid $CTTY sh -i
fi

echo "Powering down."
mount -n -o remount,ro /
if [ -d /run/initramfs/etc ]; then
    echo " rd.debug=0 " >> /run/initramfs/etc/cmdline
fi
poweroff -f

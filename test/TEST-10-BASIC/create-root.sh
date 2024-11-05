#!/bin/sh

trap 'poweroff -f' EXIT
set -ex

# populate TEST_FSTYPE
. /env

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zpool create dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
    zfs create dracut/root
else
    eval "mkfs.${TEST_FSTYPE} -q -L dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root"
fi

mkdir -p /root

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zfs set mountpoint=/root dracut/root
    zfs get mounted dracut/root
else
    mount -t "${TEST_FSTYPE}" /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /root
fi

cp -a -t /root /source/*
mkdir -p /root/run

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zfs unmount /root
    zfs set mountpoint=/ dracut/root
else
    umount /root
fi

echo "dracut-root-block-created" | dd oflag=direct,dsync status=none of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

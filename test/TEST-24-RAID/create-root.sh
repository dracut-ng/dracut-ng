#!/bin/sh

trap 'poweroff -f' EXIT
set -e

# populate TEST_FSTYPE
. /env

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zpool create dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[12]
    zfs create dracut/root
else
    mkfs.btrfs -q -draid0 -mraid0 -L root /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[12]
    udevadm settle
    btrfs device scan
fi

udevadm settle
mkdir -p /sysroot

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zfs set mountpoint=/sysroot dracut/root
    zfs get mounted dracut/root
else
    mount -t btrfs /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid1 /sysroot
fi

cp -a -t /sysroot /source/*
umount /sysroot

echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f

#!/bin/sh

trap 'poweroff -f' EXIT
set -e

mkfs.ext4 -q -L '  rdinit=/bin/sh' /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
mkdir -p /root
mount -t ext4 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /root
cp -a -t /root /source/*
mkdir -p /root/run
umount /root
echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
poweroff -f

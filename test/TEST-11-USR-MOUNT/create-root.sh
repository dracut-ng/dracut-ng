#!/bin/sh

trap 'poweroff -f' EXIT
set -e

modprobe btrfs || :
mkfs.btrfs -q -L dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
btrfs device scan /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
mkdir -p /root
mount -t btrfs /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /root
btrfs subvolume create /root/usr
cp -a -t /root /source/*
mkdir -p /root/run
btrfs filesystem sync /root
umount /root
echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
poweroff -f

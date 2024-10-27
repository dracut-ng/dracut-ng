#!/bin/sh

trap 'poweroff -f' EXIT
set -e

modprobe btrfs || :
mkfs.btrfs -q -L dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
mkfs.btrfs -q -L dracutusr /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_usr
btrfs device scan /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root
btrfs device scan /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_usr
mkdir -p /root
mount -t btrfs /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /root
[ -d /root/usr ] || mkdir -p /root/usr
mount -t btrfs /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_usr /root/usr
btrfs subvolume create /root/usr/usr
umount /root/usr
mount -t btrfs -o subvol=usr /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_usr /root/usr
cp -a -t /root /source/*
mkdir -p /root/run
btrfs filesystem sync /root/usr
btrfs filesystem sync /root
umount /root/usr
umount /root
echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
poweroff -f

#!/bin/sh

trap 'poweroff -f' EXIT
set -ex

mdadm --create /dev/md0 --run --level=stripe --raid-devices=2 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid0-1 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid0-2
mdadm -W /dev/md0 || :
lvm pvcreate -ff -y /dev/md0
lvm vgcreate dracut /dev/md0
lvm lvcreate --yes -l 100%FREE -n root dracut
lvm vgchange -ay
mkfs.ext4 -q -L sysroot /dev/dracut/root
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
umount /sysroot
lvm lvchange -a n /dev/dracut/root
mdadm -W /dev/md0 || :
mdadm --stop /dev/md0
echo "dracut-root-block-created" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f

#!/bin/sh

trap 'poweroff -f' EXIT
set -ex
modprobe dm_thin_pool
for dev in /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk[123]; do
    lvm pvcreate -ff -y "$dev"
done

lvm vgcreate dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk[123]
lvm lvcreate --yes --ignoremonitoring -l 100%FREE -T dracut/mythinpool
lvm lvcreate --yes --ignoremonitoring -V200M -T dracut/mythinpool -n root
lvm vgchange --ignoremonitoring -ay
mkfs.ext4 -q /dev/dracut/root
mkdir -p /sysroot
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
umount /sysroot
lvm lvchange -a n /dev/dracut/root

if ! dmsetup status | grep -q out_of_data_space; then
    echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
fi

sync
poweroff -f

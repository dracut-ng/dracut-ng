#!/bin/sh

trap 'poweroff -f' EXIT
set -ex
printf test > keyfile
cryptsetup -q luksFormat /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk1 /keyfile
cryptsetup -q luksFormat /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk2 /keyfile
cryptsetup luksOpen /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk1 dracut_disk1 < /keyfile
cryptsetup luksOpen /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk2 dracut_disk2 < /keyfile
mdadm --create /dev/md0 --run --auto=yes --level=1 --metadata=0.90 --raid-devices=2 /dev/mapper/dracut_disk1 /dev/mapper/dracut_disk2
# wait for the array to finish initializing, otherwise this sometimes fails
# randomly.
mdadm -W /dev/md0
lvm pvcreate -ff -y /dev/md0
lvm vgcreate dracut /dev/md0

lvm lvcreate --yes -l 100%FREE -n root dracut
lvm vgchange -ay
mkfs.ext4 -q /dev/dracut/root
mkdir -p /sysroot
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
umount /sysroot
lvm lvchange -a n /dev/dracut/root
mdadm -W /dev/md0 || :
mdadm --stop /dev/md0
cryptsetup luksClose /dev/mapper/dracut_disk1
cryptsetup luksClose /dev/mapper/dracut_disk2

{
    echo "dracut-root-block-created"
    for i in /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk[123]; do
        udevadm info --query=property --name="$i" | grep -F 'ID_FS_UUID='
    done
} | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f

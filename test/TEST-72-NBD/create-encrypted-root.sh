#!/bin/sh

trap 'poweroff -f' EXIT
set -ex

printf test > keyfile
cryptsetup -q luksFormat /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /keyfile
echo "The passphrase is test"
cryptsetup luksOpen /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root dracut_crypt_test < /keyfile
lvm pvcreate -ff -y /dev/mapper/dracut_crypt_test
lvm vgcreate dracut /dev/mapper/dracut_crypt_test
lvm lvcreate --yes -l 100%FREE -n root dracut
lvm vgchange -ay
udevadm settle
mkfs.ext4 -q -L dracut -j /dev/dracut/root
mkdir -p /sysroot
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
umount /sysroot
sleep 1
lvm lvchange -a n /dev/dracut/root
udevadm settle
cryptsetup luksClose /dev/mapper/dracut_crypt_test
udevadm settle
sleep 1
{
    echo "dracut-root-block-created"
    udevadm info --query=property --name=/dev/disk/by-id/ata-disk_root --property=ID_FS_UUID
} | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f

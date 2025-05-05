#!/bin/sh

trap 'poweroff -f' EXIT

# dmraid does not want symlinks in --disk "..."
echo y | dmraid -f isw -C Test0 --type 1 --disk "$(realpath /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk1) $(realpath /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk2)"
udevadm settle

SETS=$(dmraid -c -s)
# scan and activate all DM RAIDS
for s in $SETS; do
    dmraid -ay -i -p --rm_partitions "$s"
    [ -e "/dev/mapper/$s" ] && kpartx -a -p p "/dev/mapper/$s"
done

udevadm settle
sleep 1
udevadm settle

sfdisk -g /dev/mapper/isw*Test0
sfdisk --no-reread /dev/mapper/isw*Test0 << EOF
,4M
,112M
,112M
,112M
EOF

set -x

udevadm settle
dmraid -a n
udevadm settle

SETS=$(dmraid -c -s -i)
# scan and activate all DM RAIDS
for s in $SETS; do
    dmraid -ay -i -p --rm_partitions "$s"
    [ -e "/dev/mapper/$s" ] && kpartx -a -p p "/dev/mapper/$s"
done

udevadm settle

mdadm --create /dev/md0 --run --auto=yes --level=5 --raid-devices=3 \
    /dev/mapper/isw*p*[234]
# wait for the array to finish initializing, otherwise this sometimes fails
# randomly.
mdadm -W /dev/md0
set -e
lvm pvcreate -ff -y /dev/md0
lvm vgcreate dracut /dev/md0
lvm lvcreate --yes -l 100%FREE -n root dracut
lvm vgchange -ay
mkfs.ext4 -q -L root /dev/dracut/root
mkdir -p /sysroot
mount -t ext4 /dev/dracut/root /sysroot
cp -a -t /sysroot /source/*
umount /sysroot
lvm lvchange -a n /dev/dracut/root
udevadm settle
mdadm --detail --export /dev/md0 | grep -F MD_UUID > /tmp/mduuid
. /tmp/mduuid
echo "MD_UUID=$MD_UUID"
{
    echo "dracut-root-block-created"
    echo MD_UUID="$MD_UUID"
} | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
mdadm --wait-clean /dev/md0
sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

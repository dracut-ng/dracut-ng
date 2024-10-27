#!/bin/sh

trap 'poweroff -f' EXIT
set -ex

# populate TEST_FSTYPE
. /env

eval "mkfs.${TEST_FSTYPE} -q -L dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root"
mkdir -p /root
mount -t "${TEST_FSTYPE}" /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /root
cp -a -t /root /source/*
mkdir -p /root/run
umount /root
echo "dracut-root-block-created" | dd oflag=direct,dsync status=none of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

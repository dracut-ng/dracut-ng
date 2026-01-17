#!/bin/sh -e

trap 'poweroff -f' EXIT

udevadm settle --timeout=30 || :

echo "testhook-done" >> /run/dracut_hook_ran
dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_testlog status=none < /run/dracut_hook_ran
sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_testlog

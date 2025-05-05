#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/console 2>&1

echo "made it to the rootfs! Powering down."
while read -r dev _ fstype opts rest || [ -n "$dev" ]; do
    [ "$fstype" != "ext4" ] && continue
    echo "iscsi-OK $dev $fstype $opts" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    break
done < /proc/mounts

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

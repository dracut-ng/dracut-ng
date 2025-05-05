#!/bin/sh
: > /dev/watchdog

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/console 2>&1

while read -r dev fs fstype opts rest || [ -n "$dev" ]; do
    [ "$dev" = "rootfs" ] && continue
    [ "$fs" != "/" ] && continue
    echo "nbd-OK $fstype $opts" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    echo "nbd-OK $fstype $opts"
    break
done < /proc/mounts
echo "made it to the rootfs! Powering down."

mount -n -o remount,ro /

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

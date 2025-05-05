#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/console 2>&1

echo "made it to the rootfs! Powering down."

set -x

for i in /sys/class/net/*; do
    # booting with network-manager module
    state=/run/NetworkManager/devices/$(cat "$i"/ifindex)
    grep -q connection-uuid= "$state" 2> /dev/null || continue
    i=${i##*/}
    [ "$i" = lo ] && continue
    ip link show "$i" | grep -q master && continue
    IFACES="${IFACES}${i} "
done

for i in /run/initramfs/net.*.did-setup; do
    # booting with network module
    [ -f "$i" ] || continue
    strglobin "$i" ":*:*:*:*:" && continue
    i=${i%.did-setup}
    IFACES="${IFACES}${i##*/net.} "
done
{
    echo "OK"
    echo "$IFACES"
} | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker
poweroff -f

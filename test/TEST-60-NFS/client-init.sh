#!/bin/sh
: > /dev/watchdog
. /lib/dracut-lib.sh
. /lib/url-lib.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec > /dev/console 2>&1

echo "made it to the rootfs! Powering down."

while read -r dev _ fstype opts rest || [ -n "$dev" ]; do
    [ "$fstype" != "nfs" ] && [ "$fstype" != "nfs4" ] && continue
    echo "nfs-OK $dev $fstype $opts" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    break
done < /proc/mounts

# fail the test of rd.live.overlay did not worked as expected
if grep -qF 'rd.live.overlay' /proc/cmdline; then
    if ! strstr "$(cat /proc/mounts)" LiveOS_rootfs; then
        echo "nfs-FAIL" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    fi
fi

if [ "$fstype" = "nfs" ] || [ "$fstype" = "nfs4" ]; then

    serverip=${dev%:*}
    path=${dev#*:}
    echo serverip="${serverip}"
    echo path="${path}"
    echo /proc/mounts status
    cat /proc/mounts

    echo test:nfs_fetch_url nfs::"${serverip}":"${path}"/root/fetchfile
    if nfs_fetch_url nfs::"${serverip}":"${path}"/root/fetchfile /run/nfsfetch.out; then
        echo nfsfetch-OK
        echo "nfsfetch-OK" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2 status=none
    fi
else
    echo nfsfetch-BYPASS fstype="${fstype}"
    echo "nfsfetch-OK" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2 status=none
fi

: > /dev/watchdog

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2
poweroff -f

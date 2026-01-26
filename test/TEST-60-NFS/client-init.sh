#!/bin/sh
: > /dev/watchdog
. /lib/dracut-lib.sh
. /lib/url-lib.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# shellcheck disable=SC2317,SC2329  # called via EXIT trap
_poweroff() {
    local exit_code="$?"

    [ "$exit_code" -eq 0 ] || echo "Error: $0 failed with exit code $exit_code."
    echo "Powering down."

    if [ -d /usr/lib/systemd/system ]; then
        # graceful poweroff
        systemctl start poweroff.target --job-mode=replace-irreversibly --no-block
    else
        # force immediate poweroff
        poweroff -f
    fi
}

trap _poweroff EXIT
exec > /dev/console 2>&1

echo "made it to the NFS client rootfs!"

while read -r dev _ fstype opts rest || [ -n "$dev" ]; do
    [ "$fstype" != "nfs" ] && [ "$fstype" != "nfs4" ] && continue
    echo "nfs-OK $dev $fstype $opts" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    break
done < /proc/mounts

# fail the test if rd.overlay did not work as expected
if grep -qF 'rd.overlay' /proc/cmdline; then
    if ! strstr "$(cat /proc/mounts)" LiveOS_rootfs; then
        echo "nfs-FAIL" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
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
        echo "nfsfetch-OK" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2 status=none
    fi
else
    echo nfsfetch-BYPASS fstype="${fstype}"
    echo "nfsfetch-OK" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2 status=none
fi

: > /dev/watchdog

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker2

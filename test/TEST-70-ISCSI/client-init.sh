#!/bin/sh

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

echo "made it to the iSCSI client rootfs!"
while read -r dev _ fstype opts rest || [ -n "$dev" ]; do
    [ "$fstype" != "ext4" ] && continue
    echo "iscsi-OK $dev $fstype $opts" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    break
done < /proc/mounts

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker

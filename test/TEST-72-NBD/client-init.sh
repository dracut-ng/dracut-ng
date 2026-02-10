#!/bin/sh
: > /dev/watchdog

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
echo "made it to the NBD client rootfs!"

while read -r dev fs fstype opts rest || [ -n "$dev" ]; do
    [ "$dev" = "rootfs" ] && continue
    [ "$fs" != "/" ] && continue
    echo "nbd-OK $fstype $opts" | dd oflag=direct of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
    echo "nbd-OK $fstype $opts"
    break
done < /proc/mounts

mount -n -o remount,ro /

sync /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker

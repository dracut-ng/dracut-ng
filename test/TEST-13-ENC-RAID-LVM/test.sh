#!/bin/bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on LVM on encrypted partitions of a RAID-5"

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell rd.break" # udev.log-priority=debug
#DEBUGFAIL="rd.shell rd.udev.log-priority=debug loglevel=70 systemd.log_target=kmsg systemd.log_target=debug"
#DEBUGFAIL="rd.shell loglevel=70 systemd.log_target=kmsg systemd.log_target=debug"

test_run() {
    LUKSARGS=$(cat "$TESTDIR"/luks.txt)

    echo "CLIENT TEST START: $LUKSARGS"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-1.img disk1
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-2.img disk2
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-3.img disk3

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=/dev/dracut/root ro rd.auto rd.retry=20 rootwait console=ttyS0,115200n81 $LUKSARGS" \
        -initrd "$TESTDIR"/initramfs.testing
    test_marker_check || return 1
    echo "CLIENT TEST END: [OK]"

    test_marker_reset

    echo "CLIENT TEST START: Any LUKS"
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=/dev/dracut/root rw rd.auto rd.retry=20 console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.testing
    test_marker_check || return 1
    echo "CLIENT TEST END: [OK]"

    test_marker_reset

    echo "CLIENT TEST START: Wrong LUKS UUID"
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=/dev/dracut/root rw rd.auto rd.luks.uuid=failme console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.testing
    test_marker_check && return 1
    echo "CLIENT TEST END: [OK]"

    return 0
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N -l --keep --tmpdir "$TESTDIR" \
        -m "test-root" \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # second, install the files needed to make the root filesystem

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -l -i "$TESTDIR"/overlay / \
        -a "test-makeroot bash crypt lvm mdraid kernel-modules" \
        -I "grep cryptsetup" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/overlay

    # Create the blank files to use as a root filesystem
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-1.img disk1 80
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-2.img disk2 80
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-3.img disk3 80

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    cryptoUUIDS=$(grep -F --binary-files=text -m 3 ID_FS_UUID "$TESTDIR"/marker.img)
    for uuid in $cryptoUUIDS; do
        eval "$uuid"
        printf ' rd.luks.uuid=luks-%s ' "$ID_FS_UUID"
    done > "$TESTDIR"/luks.txt

    i=1
    for uuid in $cryptoUUIDS; do
        eval "$uuid"
        printf 'luks-%s /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_disk%s /etc/key timeout=0\n' "$ID_FS_UUID" $i
        ((i += 1))
    done > /tmp/crypttab
    echo -n test > /tmp/key
    chmod 0600 /tmp/key

    test_dracut \
        -i "./cryptroot-ask.sh" "/sbin/cryptroot-ask" \
        -i "/tmp/crypttab" "/etc/crypttab" \
        -i "/tmp/key" "/etc/key" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

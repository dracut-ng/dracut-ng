#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="no (xfs) driver on root filesystem"

test_check() {
    if ! type -p mkfs.xfs &> /dev/null; then
        echo "Test needs mkfs.xfs.. Skipping"
        return 1
    fi

    if ! command -v systemctl > /dev/null; then
        echo "This test needs systemd to run."
        return 1
    fi
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell=1 rd.break=pre-mount"
test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root
    qemu_add_drive disk_index disk_args "$TESTDIR"/mnt.img mnt

    test_marker_reset

    # This test should fail if rd.driver.export is not passed at kernel command-line
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE rd.driver.export" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    call_dracut --tmpdir "$TESTDIR" \
        --no-kernel \
        --add "systemd-udevd systemd-journald systemd-tmpfiles systemd-ldconfig systemd-ask-password shutdown" \
        --mount "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_mnt /mnt xfs rw" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root
    mkdir -p "$TESTDIR"/overlay/source
    mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source
    rm -rf "$TESTDIR"/dracut.*

    # make sure no linux kernel driver is included in the rootfs
    rm -rf "$TESTDIR"/overlay/source/lib/modules/*

    # make sure /lib/modules directory exists inside the rootfs
    mkdir -p "$TESTDIR"/overlay/source/lib/modules "$TESTDIR"/overlay/source/mnt

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    call_dracut -i "$TESTDIR"/overlay / \
        --add-confdir "test-makeroot" \
        -I "mkfs.xfs" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot

    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/mnt.img mnt 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created
    rm -- "$TESTDIR"/marker.img

    test_dracut \
        --add-drivers xfs \
        --add kernel-modules-export
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

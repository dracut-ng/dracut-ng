#!/usr/bin/env bash
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a btrfs filesystem with /usr subvolume"

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell rd.break"

test_check() {
    if ! type -p mkfs.btrfs &> /dev/null; then
        echo "Test needs mkfs.btrfs.. Skipping"
        return 1
    fi
}

client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE $client_opts" \
        -initrd "$TESTDIR"/initramfs.testing

    if ! test_marker_check; then
        echo "CLIENT TEST END: $test_name [FAILED]"
        return 1
    fi
    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    client_run "no option specified"
    client_run "readonly root and writeable /usr" "ro"
    client_run "writeable root and /usr" "rw"
    client_run "readonly root and /usr" "ro rd.fstab=0"
    client_run "readonly root snapshot" "rd.fstab=0 subvol=snapshot-root"
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    call_dracut --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        --mount "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root /usr btrfs subvol=usr,rw" \
        -f "$TESTDIR"/initramfs.root
    mkdir -p "$TESTDIR"/overlay/source
    mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source
    rm -rf "$TESTDIR"/dracut.*

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    call_dracut -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -I "mkfs.btrfs" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot

    # Create the blank file to use as a root filesystem
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot

    if ! test_marker_check dracut-root-block-created; then
        echo "Could not create root filesystem"
        return 1
    fi

    test_dracut \
        --add-drivers "btrfs"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

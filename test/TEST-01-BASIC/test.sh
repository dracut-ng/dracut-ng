#!/bin/bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a ext4 filesystem"

# Uncomment this to debug failures
# DEBUGFAIL="rd.shell rd.break"

test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE rw \"root=LABEL=  rdinit=/bin/sh\" rd.retry=3" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    test_marker_check || return 1
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
        -a "test-makeroot" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 80

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    rm -- "$TESTDIR"/marker.img

    # make sure --omit-drivers does not filter out drivers using regexp to test for an earlier regression (assuming there is no one letter linux kernel module needed to run the test)
    test_dracut \
        --omit-drivers 'a b c d e f g h i j k l m n o p q r s t u v w x y z' \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

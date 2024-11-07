#!/usr/bin/env bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on ${TEST_FSTYPE} filesystem"

# Uncomment this to debug failures
# DEBUGFAIL="rd.shell rd.break"

test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    if [ "$TEST_FSTYPE" = "zfs" ]; then
        TEST_KERNEL_CMDLINE+=" root=ZFS=dracut/root "
    else
        TEST_KERNEL_CMDLINE+=" root=LABEL=dracut "
    fi

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    test_marker_check || return 1
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N -l --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # pass enviroment variables to make the root filesystem
    echo "TEST_FSTYPE=${TEST_FSTYPE}" > "$TESTDIR"/overlay/env

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.

    # shellcheck disable=SC2046
    "$DRACUT" -N -l -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; else echo "-I mkfs.${TEST_FSTYPE}"; fi) \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    rm -- "$TESTDIR"/marker.img

    # shellcheck disable=SC2046
    test_dracut \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; fi) \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

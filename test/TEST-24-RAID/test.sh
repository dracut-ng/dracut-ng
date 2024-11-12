#!/usr/bin/env bash

if [ "$TEST_FSTYPE" != "zfs" ]; then
    export TEST_FSTYPE="btrfs"
fi

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on multiple device $TEST_FSTYPE"

test_check() {
    if ! type -p mkfs.btrfs &> /dev/null; then
        echo "Test needs mkfs.btrfs.. Skipping"
        return 1
    fi
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell"
test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-1.img raid1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-2.img raid2

    if [ "$TEST_FSTYPE" = "zfs" ]; then
        TEST_KERNEL_CMDLINE+=" root=ZFS=dracut/root "
    else
        TEST_KERNEL_CMDLINE+=" root=LABEL=root "
    fi

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE ro" \
        -initrd "$TESTDIR"/initramfs.testing
    test_marker_check || return 1
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
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
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -d "btrfs piix ide-gd_mod ata_piix sd_mod" \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; else echo "-I mkfs.${TEST_FSTYPE}"; fi) \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    # Create the blank files to use as a root filesystem
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-1.img raid1 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-2.img raid2 1

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1

    test_marker_check dracut-root-block-created || return 1

    # shellcheck disable=SC2046
    test_dracut \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; fi) \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

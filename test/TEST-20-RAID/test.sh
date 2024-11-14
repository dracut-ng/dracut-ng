#!/usr/bin/env bash

[ -z "$TEST_FSTYPE" ] && TEST_FSTYPE="ext4"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on multiple device $TEST_FSTYPE"

test_check() {
    (command -v zfs || (command -v mdadm && command -v "mkfs.$TEST_FSTYPE")) &> /dev/null
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
    elif [ "$TEST_FSTYPE" = "btrfs" ]; then
        TEST_KERNEL_CMDLINE+=" root=LABEL=root "
    else
        TEST_KERNEL_CMDLINE+=" root=/dev/dracut/root rd.auto"
    fi

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE ro" \
        -initrd "$TESTDIR"/initramfs.testing || return 1
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
        -a "lvm mdraid" \
        -I "grep" \
        $(if command -v cryptsetup > /dev/null; then echo "-a crypt -I cryptsetup"; fi) \
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

    if command -v cryptsetup > /dev/null; then
        eval "$(grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img)"
        echo "testluks UUID=$ID_FS_UUID /etc/key" > /tmp/crypttab
        echo -n "test" > /tmp/key
    fi

    # shellcheck disable=SC2046
    test_dracut \
        -a "lvm mdraid" \
        $(if command -v cryptsetup > /dev/null; then echo "-a crypt"; fi) \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; fi) \
        -i "./cryptroot-ask.sh" "/sbin/cryptroot-ask" \
        -i "/tmp/crypttab" "/etc/crypttab" \
        -i "/tmp/key" "/etc/key" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

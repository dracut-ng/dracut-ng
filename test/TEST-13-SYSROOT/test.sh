#!/usr/bin/env bash
set -e
# shellcheck disable=SC2034
TEST_DESCRIPTION="initramfs created from sysroot"

test_check() {
    set_kversion_and_vmlinux
}

test_run() {
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    # create root filesystem
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync "$TESTDIR"/root.img
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync "$TESTDIR"/root.img

    ln -s / "$TESTDIR"/sysroot
    test_dracut --sysroot "$TESTDIR"/sysroot
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

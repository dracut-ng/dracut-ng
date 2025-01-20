#!/usr/bin/env bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on ext4 filesystem"

test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    test_marker_check || return 1
}

test_setup() {
    # create root filesystem
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1

    # Create the blank file to use as a root filesystem
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 1
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync

    test_dracut \
        --omit systemd \
        --kernel-cmdline "$TEST_KERNEL_CMDLINE root=LABEL=dracut" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="Test overlayfs module with persistent device overlay"

test_run() {
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0

    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root
    qemu_add_drive disk_index disk_args "$TESTDIR"/overlay.img overlay

    test_marker_reset

    echo "TEST: tmpfs overlay"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut rd.overlayfs=1" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: persistent device overlay (LABEL=OVERLAY)"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut rd.overlay=LABEL=OVERLAY" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: persistent device overlay (UUID=$OVERLAY_UUID)"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut rd.overlay=UUID=$OVERLAY_UUID" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: fallback to tmpfs (non-existent LABEL)"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut rd.overlay=LABEL=NONEXISTENT" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: overlayroot=LABEL (cloud-initramfs-tools compatibility)"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut overlayroot=LABEL=OVERLAY" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: overlayroot=device:dev=UUID (cloud-initramfs-tools syntax)"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut overlayroot=device:dev=UUID=$OVERLAY_UUID" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
    test_marker_reset

    echo "TEST: overlayroot=tmpfs"
    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut overlayroot=tmpfs" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    call_dracut --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -i ./test-overlayfs.sh /sbin/init \
        -f "$TESTDIR"/initramfs.root

    build_ext4_image "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img dracut

    dd if=/dev/zero of="$TESTDIR"/overlay.img bs=1M count=100
    mkfs.ext4 -L OVERLAY "$TESTDIR"/overlay.img
    # shellcheck disable=SC2034
    OVERLAY_UUID=$(blkid -s UUID -o value "$TESTDIR"/overlay.img)

    call_dracut --tmpdir "$TESTDIR" \
        --add overlayfs \
        -f "$TESTDIR"/initramfs.testing
}

test_cleanup() {
    return 0
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

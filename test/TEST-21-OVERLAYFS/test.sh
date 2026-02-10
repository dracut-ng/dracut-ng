#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="Test overlayfs module with persistent device overlay"

# Uncomment this to debug failures
#DEBUGFAIL="rd.debug rd.shell"

client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    client_test_start "$test_name"

    declare -a disk_args=()
    qemu_add_drive disk_args "$TESTDIR"/root.img root
    qemu_add_drive disk_args "$TESTDIR"/overlay.img overlay

    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut $client_opts" \
        -initrd "$TESTDIR"/initramfs.testing
    check_qemu_log

    client_test_end
}

test_run() {
    local overlay_uuid
    overlay_uuid=$(blkid -s UUID -o value "$TESTDIR"/overlay.img)

    client_run "overlay disabled (rd.overlay=0)" "rd.overlay=0 test.expect=none"
    client_run "tmpfs overlay (rd.overlay)" "rd.overlay test.expect=tmpfs"
    client_run "tmpfs overlay (rd.overlay=1)" "rd.overlay=1 test.expect=tmpfs"
    client_run "persistent device overlay (LABEL)" "rd.overlay=LABEL=OVERLAY test.expect=device"
    client_run "persistent device overlay (UUID)" "rd.overlay=UUID=$overlay_uuid test.expect=device"
    client_run "persistent device overlay (device path)" \
        "rd.overlay=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_overlay test.expect=device"
    client_run "fallback to tmpfs (non-existent LABEL)" "rd.overlay=LABEL=NONEXISTENT test.expect=tmpfs"
}

test_setup() {
    build_client_rootfs "$TESTDIR/rootfs"
    build_ext4_image "$TESTDIR/rootfs" "$TESTDIR"/root.img dracut

    rm -f "$TESTDIR"/overlay.img
    truncate -s 32M "$TESTDIR"/overlay.img
    mkfs.ext4 -q -L OVERLAY "$TESTDIR"/overlay.img

    test_dracut --add overlayfs
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

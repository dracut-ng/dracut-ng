#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="kernel-install with root filesystem on ext4 filesystem"

test_check() {
    if ! command -v kernel-install > /dev/null; then
        echo "This test needs kernel-install to run."
        return 1
    fi
}

test_run() {
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE" \
        -initrd "$BOOT_ROOT/$TOKEN/$KVERSION"/initrd

    test_marker_check

    test_marker_reset

    # rescue (non-hostonly) boot
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE" \
        -initrd "$BOOT_ROOT/$TOKEN"/0-rescue/initrd

    test_marker_check
}

test_setup() {
    # create root filesystem
    # shellcheck disable=SC2153
    call_dracut --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root

    KVERSION=$(determine_kernel_version "$TESTDIR"/initramfs.root)
    KIMAGE=$(determine_kernel_image "$KVERSION")

    build_ext4_image "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img dracut

    mkdir -p /run/kernel /run/initramfs/dracut.conf.d
    echo 'initrd_generator=dracut' >> /run/kernel/install.conf

    # enable test dracut config
    cp "${basedir}"/dracut.conf.d/test/*.conf /run/initramfs/dracut.conf.d/

    # enable rescue boot config
    cp "${basedir}"/dracut.conf.d/rescue/*.conf /run/initramfs/dracut.conf.d/

    # using kernell-install to invoke dracut
    mkdir -p "$BOOT_ROOT/$TOKEN/$KVERSION" "$BOOT_ROOT/loader/entries" "$BOOT_ROOT/$TOKEN/0-rescue/loader/entries"
    kernel-install add "$KVERSION" "$KIMAGE"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

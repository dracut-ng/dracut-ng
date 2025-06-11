#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="kernel-install with root filesystem on ext4 filesystem"

test_check() {
    if command -v systemd-detect-virt > /dev/null && ! systemd-detect-virt -c &> /dev/null; then
        echo "This test assumes that it runs inside a CI container."
        return 1
    fi

    if ! command -v kernel-install > /dev/null; then
        echo "This test needs kernel-install to run."
        return 1
    fi

    if [[ $(kernel-install --version | grep -oP '(?<=systemd )\d+') -lt 255 ]]; then
        echo "This test requires support for kernel-install add-all (v255)"
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
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync "$TESTDIR"/root.img
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync "$TESTDIR"/root.img

    mkdir -p /run/kernel
    echo 'initrd_generator=dracut' >> /run/kernel/install.conf

    # enable test dracut config
    cp /usr/lib/dracut/test/dracut.conf.d/test/test.conf /usr/lib/dracut/dracut.conf.d/

    # enable rescue boot config
    cp /usr/lib/dracut/dracut.conf.d/rescue/50-rescue.conf /usr/lib/dracut/dracut.conf.d/

    # using kernell-install to invoke dracut
    mkdir -p "$BOOT_ROOT/$TOKEN/$KVERSION" "$BOOT_ROOT/loader/entries" "$BOOT_ROOT/$TOKEN/0-rescue/loader/entries"
    kernel-install add-all
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

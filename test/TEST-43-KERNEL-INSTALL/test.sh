#!/usr/bin/env bash
set -e
# shellcheck disable=SC2034
TEST_DESCRIPTION="kernel-install with root filesystem on ext4 filesystem"

test_check() {
    if command -v systemd-detect-virt > /dev/null && ! systemd-detect-virt -c &> /dev/null; then
        echo "This test assumes that it runs inside a CI container."
        return 1
    fi

    if ! command -v kernel-install > /dev/null && ! command -v installkernel > /dev/null; then
        echo "This test needs kernel-install or installkernel to run."
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

    if command -v kernel-install > /dev/null; then
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
    else
        "$testdir"/run-qemu \
            "${disk_args[@]}" \
            -append "$TEST_KERNEL_CMDLINE" \
            -initrd "$VMLINUZ/../initramfs-$KVERSION.img"
    fi

    test_marker_check
}

test_setup() {
    # create root filesystem
    # shellcheck disable=SC2153
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync

    mkdir -p /run/kernel
    echo 'initrd_generator=dracut' >> /run/kernel/install.conf
    echo 'uki_generator=none' >> /run/kernel/install.conf

    # enable test dracut config
    cp /usr/lib/dracut/test/dracut.conf.d/test/test.conf /usr/lib/dracut/dracut.conf.d/

    # enable rescue boot config
    cp /usr/lib/dracut/dracut.conf.d/rescue/50-rescue.conf /usr/lib/dracut/dracut.conf.d/

    if command -v kernel-install > /dev/null; then
        # bls is the default, but lets set it explicitly
        echo 'layout=bls' >> /run/kernel/install.conf
        # using kernel-install to invoke dracut
        mkdir -p "$BOOT_ROOT/$TOKEN/$KVERSION" "$BOOT_ROOT/loader/entries" "$BOOT_ROOT/$TOKEN/0-rescue/loader/entries"
        KERNEL_INSTALL_CONF_ROOT=/run/kernel kernel-install add "$KVERSION" "$VMLINUZ"
    else
        # compat is the default, but lets set it explicitly
        echo 'layout=compat' >> /run/kernel/install.conf
        # using installkernel to invoke dracut
        INSTALLKERNEL_CONF_ROOT=/run/kernel installkernel "$KVERSION" "$VMLINUZ"
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

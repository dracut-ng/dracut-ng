#!/usr/bin/env bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="live root on a squash filesystem"

# Uncomment these to debug failures
#DEBUGFAIL="rd.shell rd.debug rd.live.debug loglevel=7"

test_check() {
    if ! type -p mksquashfs &> /dev/null; then
        echo "Test needs mksquashfs... Skipping"
        return 1
    fi
}

client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root
    qemu_add_drive disk_index disk_args "$TESTDIR"/root_erofs.img root_erofs

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$client_opts" \
        -initrd "$TESTDIR"/initramfs.testing

    if ! test_marker_check; then
        echo "CLIENT TEST END: $test_name [FAILED]"
        return 1
    fi
    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    client_run "overlayfs" "" || return 1

    # The remaining subtests are not yet passing on arm, bail out
    if [[ ${DRACUT_ARCH:-$(uname -m)} == arm* || ${DRACUT_ARCH:-$(uname -m)} == aarch64 ]]; then
        return 0
    fi

    client_run "live" "rd.live.image" || return 1
    client_run "livedir" "rd.live.image rd.live.dir=testdir" || return 1

    # Run the erofs test only if mkfs.erofs is available
    if command -v mkfs.erofs &> /dev/null; then
        client_run "erofs" "root=live:/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root_erofs" || return 1
    fi

    test_marker_reset
    rootPartitions=$(sfdisk -d "$TESTDIR"/root.img | grep -c 'root\.img[0-9]')
    [ "$rootPartitions" -eq 1 ] || return 1

    client_run "autooverlay" "init=/sbin/init-persist rd.live.image rd.live.overlay=LABEL=persist rd.live.dir=testdir" || return 1

    rootPartitions=$(sfdisk -d "$TESTDIR"/root.img | grep -c 'root\.img[0-9]')
    [ "$rootPartitions" -eq 2 ] || return 1

    (
        # Ensure that this test works when run with the `V=1` parameter, which runs the script with `set -o pipefail`.
        set +o pipefail

        # Verify that the string "dracut-autooverlay-success" occurs in the second partition in the image file.
        dd if="$TESTDIR"/root.img bs=1MiB status=none \
            | grep -U --binary-files=binary -F -m 1 -q dracut-autooverlay-success
    ) || return 1

    return 0
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -i ./test-init.sh /sbin/init-persist \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/rootfs && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/rootfs && rm -rf "$TESTDIR"/dracut.*

    # test to make sure /proc /sys and /dev is not needed inside the generated initrd
    rm -rf "$TESTDIR"/rootfs/proc "$TESTDIR"/rootfs/sys "$TESTDIR"/rootfs/dev

    # speed up test run
    rm -rf "$TESTDIR"/rootfs/usr/lib/firmware

    mkdir -p "$TESTDIR"/testdir
    mksquashfs "$TESTDIR"/rootfs/ "$TESTDIR"/testdir/rootfs.img -quiet

    # Create the blank file to use as a root filesystem
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 1

    sfdisk "$TESTDIR"/root.img << EOF
2048,652688
EOF

    sync
    dd if=/dev/zero of="$TESTDIR"/ext4.img bs=512 count=652688 status=none && sync
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/rootfs/ "$TESTDIR"/ext4.img && sync
    dd if="$TESTDIR"/ext4.img of="$TESTDIR"/root.img bs=512 seek=2048 conv=noerror,sync,notrunc

    # erofs drive
    qemu_add_drive disk_index disk_args "$TESTDIR"/root_erofs.img root_erofs 1

    # Write the erofs compressed filesystem to the partition
    if command -v mkfs.erofs &> /dev/null; then
        mkfs.erofs "$TESTDIR"/root_erofs.img "$TESTDIR"/rootfs/
    fi

    test_dracut \
        --no-hostonly \
        --modules "dmsquash-live-autooverlay" \
        --kernel-cmdline "$TEST_KERNEL_CMDLINE rd.live.overlay.overlayfs=1 root=live:/dev/disk/by-label/dracut" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

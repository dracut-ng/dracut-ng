#!/bin/bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on multiple device btrfs"

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell"
test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-1.img raid1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-2.img raid2
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-3.img raid3
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-4.img raid4

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=root rw rd.retry=3" \
        -initrd "$TESTDIR"/initramfs.testing
    test_marker_check || return 1
}

test_setup() {
    # Create the blank file to use as a root filesystem
    DISKIMAGE=$TESTDIR/TEST-15-BTRFSRAID-root.img
    rm -f -- "$DISKIMAGE"
    dd if=/dev/zero of="$DISKIMAGE" bs=1M count=1024

    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N -l --keep --tmpdir "$TESTDIR" \
        -m "test-root" \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -l -i "$TESTDIR"/overlay / \
        -a "test-makeroot bash btrfs rootfs-block kernel-modules" \
        -d "piix ide-gd_mod ata_piix btrfs sd_mod" \
        -I "mkfs.btrfs" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    rm -rf -- "$TESTDIR"/overlay

    # Create the blank files to use as a root filesystem
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-1.img raid1 150
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-2.img raid2 150
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-3.img raid3 150
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid-4.img raid4 150

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1

    test_marker_check dracut-root-block-created || return 1

    test_dracut \
        -d "btrfs" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

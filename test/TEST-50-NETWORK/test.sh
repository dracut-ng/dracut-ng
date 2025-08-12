#!/usr/bin/env bash
set -e

[ -z "${USE_NETWORK-}" ] && USE_NETWORK="network"

# shellcheck disable=SC2034
TEST_DESCRIPTION="bring up network without netroot set with $USE_NETWORK"

test_run() {
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu \
        -nic user,id=lan0,net=10.0.2.0/24,dhcpstart=10.0.2.15,model=virtio-net-pci \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE rd.neednet=1 net.ifnames=0" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    # create root filesystem
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        -I "ip" \
        -i "./assertion.sh" "/assertion.sh" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync "$TESTDIR"/root.img
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync "$TESTDIR"/root.img

    test_dracut --add-drivers "virtio_net" --add "$USE_NETWORK"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

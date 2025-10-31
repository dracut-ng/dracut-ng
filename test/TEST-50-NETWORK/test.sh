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
        -device "virtio-net-pci,netdev=lan0" \
        -netdev "user,id=lan0,net=10.0.2.0/24,dhcpstart=10.0.2.15" \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE rd.neednet=1 net.ifnames=0" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    # create root filesystem
    call_dracut --tmpdir "$TESTDIR" \
        -I "ip" \
        -i "./assertion.sh" "/assertion.sh" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    build_ext4_image "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img dracut

    test_dracut --add-drivers "virtio_net" --add "qemu-net $USE_NETWORK"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

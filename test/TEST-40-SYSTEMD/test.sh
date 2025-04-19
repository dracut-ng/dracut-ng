#!/usr/bin/env bash
set -e
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a ext4 filesystem"

test_check() {
    command -v systemctl &> /dev/null
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell=1 rd.break=pre-mount"
test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE \"root=LABEL=  rdinit=/bin/sh\" systemd.log_target=console init=/sbin/init" \
        -initrd "$TESTDIR"/initramfs.testing

    test_marker_check
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION"
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir "test-makeroot" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION"

    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created
    rm -- "$TESTDIR"/marker.img

    # systemd-analyze.sh calls man indirectly
    # make the man command succeed always

    #make sure --omit-drivers does not filter out drivers using regexp to test for an earlier regression (assuming there is no one letter linux kernel module needed to run the test)

    test_dracut \
        --omit-drivers 'a b c d e f g h i j k l m n o p q r s t u v w x y z' \
        -i ./systemd-analyze.sh /lib/dracut/hooks/pre-pivot/00-systemd-analyze.sh \
        -i "/bin/true" "/usr/bin/man"

    # shellcheck disable=SC2144 # We're not installing multilib libfido2, so
    # glob will only match once. More matches would break the test anyway.
    if pkg-config --exists "libsystemd >= 257" && [ -e /usr/lib*/libfido2.so.1 ] \
        && ! lsinitrd "$TESTDIR"/initramfs.testing | grep -E ' usr/lib[^/]*/libfido2\.so\.1\b' > /dev/null; then
        echo "Error: libfido2.so.1 should have been included in the initramfs" >&2
        return 1
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

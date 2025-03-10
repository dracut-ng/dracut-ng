#!/usr/bin/env bash
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a ext4 filesystem with systemd but without dracut-systemd"

test_check() {
    command -v systemctl &> /dev/null
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell=1 rd.break=pre-mount"
client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE $client_opts" \
        -initrd "$TESTDIR"/initramfs.testing

    if ! test_marker_check; then
        echo "CLIENT TEST END: $test_name [FAILED]"
        return 1
    fi
    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    client_run "readonly root" "ro"
    client_run "writeable root" "rw"
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
        --add-confdir test-makeroot \
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

    # initrd for test infra and required kernel modules
    # Improve boot time by generating two initrds. Do not re-compress kernel modules
    test_dracut \
        --no-compress \
        -m "kernel-modules" \
        "$TESTDIR"/initramfs-test

    # vanilla kernel-independent systemd-based minimal initrd without dracut specific customizations
    # since dracut-systemd is not included in the generated initrd, only systemd options are supported during boot
    test_dracut --no-kernel \
        --omit "test systemd-sysctl systemd-modules-load" \
        -m "systemd-initrd" \
        "$TESTDIR"/initramfs-systemd-initrd

    # verify that dracut systemd services are not included
    (
        cd "$TESTDIR"/initrd/dracut.*/initramfs/usr/lib/systemd/system/
        for f in dracut*.service; do
            [ -e "$f" ] && echo "unexpected dracut service found: $f" && return 1
        done
    )

    # combine systemd-based initrd with the test infra initrd
    cat "$TESTDIR"/initramfs-test "$TESTDIR"/initramfs-systemd-initrd > "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

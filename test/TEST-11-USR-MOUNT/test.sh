#!/usr/bin/env bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a btrfs filesystem with /usr subvolume"

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell rd.break"

test_check() {
    if ! type -p mkfs.btrfs &> /dev/null; then
        echo "Test needs mkfs.btrfs.. Skipping"
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
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root
    qemu_add_drive disk_index disk_args "$TESTDIR"/usr.btrfs usr

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE $client_opts" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    if ! test_marker_check; then
        echo "CLIENT TEST END: $test_name [FAILED]"
        return 1
    fi
    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    client_run "no option specified" || return 1
    client_run "readonly root" "ro" || return 1
    client_run "writeable root" "rw" || return 1
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -i ./fstab /etc/fstab \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -I "mkfs.btrfs" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    # Create the blank file to use as a root filesystem
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/usr.btrfs usr 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1

    if ! test_marker_check dracut-root-block-created; then
        echo "Could not create root filesystem"
        return 1
    fi

    test_dracut \
        -d "btrfs"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

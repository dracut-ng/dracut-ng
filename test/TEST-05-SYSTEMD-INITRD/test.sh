#!/bin/bash
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
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut rw systemd.log_target=console rd.retry=3 init=/sbin/init" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    test_marker_check || return 1
}

test_setup() {
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
        -m "test-makeroot" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root 80

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    rm -- "$TESTDIR"/marker.img

    # directory for test configurations
    mkdir -p /tmp/dracut.conf.d

    # grab the distro configuration from the host and make it available for the tests
    if [ -d /usr/lib/dracut/dracut.conf.d ]; then
        cp -a /usr/lib/dracut/dracut.conf.d /tmp/
    fi

    # pick up configuration from /tmp/dracut.conf.d when running the tests
    TEST_DRACUT_ARGS+=" --local --confdir /tmp/dracut.conf.d --no-early-microcode --force --kver $KVERSION"

    # include $TESTDIR"/overlay if exists
    if [ -d "$TESTDIR"/overlay ]; then
        TEST_DRACUT_ARGS+=" --include $TESTDIR/overlay /"
    fi

    # shellcheck disable=SC2162
    IFS=' ' read -a TEST_DRACUT_ARGS_ARRAY <<< "$TEST_DRACUT_ARGS"

    "$DRACUT" \
        --kernel-cmdline "rd.retry=10 rd.info rd.shell=0" \
        "${TEST_DRACUT_ARGS_ARRAY[@]}" \
        -m "kernel-modules systemd-initrd qemu test-root" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

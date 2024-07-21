#!/bin/bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on LVM PV on a isw dmraid"

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell"
#DEBUGFAIL="$DEBUGFAIL udev.log-priority=debug"

client_run() {
    echo "CLIENT TEST START: $*"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-1.img disk1
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-2.img disk2

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE $* root=LABEL=root rw rd.retry=5" \
        -initrd "$TESTDIR"/initramfs.testing || return 1

    if ! test_marker_check; then
        echo "CLIENT TEST END: $* [FAIL]"
        return 1
    fi

    echo "CLIENT TEST END: $* [OK]"
    return 0
}

test_run() {
    read -r MD_UUID < "$TESTDIR"/mduuid
    if [[ -z $MD_UUID ]]; then
        echo "Setup failed"
        return 1
    fi

    client_run rd.auto rd.md.imsm=0 || return 1
    client_run rd.md.uuid="$MD_UUID" rd.dm=0 || return 1
    # This test succeeds, because the mirror parts are found without
    # assembling the mirror itself, which is what we want
    client_run rd.md.uuid="$MD_UUID" rd.md=0 rd.md.imsm failme && return 1
    client_run rd.md.uuid="$MD_UUID" rd.md=0 failme && return 1
    # the following test hangs on newer md
    client_run rd.md.uuid="$MD_UUID" rd.dm=0 rd.md.imsm rd.md.conf=0 || return 1
    return 0
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
        -m "test-makeroot bash lvm mdraid dmraid kernel-modules" \
        -d "piix ide-gd_mod ata_piix ext4 sd_mod dm-multipath dm-crypt dm-round-robin faulty linear multipath raid0 raid10 raid1 raid456" \
        -I "grep sfdisk realpath" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/overlay

    # Create the blank files to use as a root filesystem
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-1.img disk1 200
    qemu_add_drive disk_index disk_args "$TESTDIR"/disk-2.img disk2 200

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    eval "$(grep -F --binary-files=text -m 1 MD_UUID "$TESTDIR"/marker.img)"

    if [[ -z $MD_UUID ]]; then
        echo "Setup failed"
        return 1
    fi

    echo "$MD_UUID" > "$TESTDIR"/mduuid

    test_dracut \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

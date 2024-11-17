#!/usr/bin/env bash

[ -z "$TEST_FSTYPE" ] && TEST_FSTYPE="ext4"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on multiple device $TEST_FSTYPE (on top of RAID and LUKS)"

test_check() {
    (command -v zfs || (command -v lvm && command -v "mkfs.$TEST_FSTYPE")) &> /dev/null
}

if [ "$TEST_FSTYPE" = "zfs" ]; then
    TEST_KERNEL_CMDLINE+=" root=ZFS=dracut/root "
elif [ "$TEST_FSTYPE" = "btrfs" ]; then
    TEST_KERNEL_CMDLINE+=" root=LABEL=root "
else
    TEST_KERNEL_CMDLINE+=" root=LABEL=root "
    export USE_LVM=1
    command -v mdadm > /dev/null && export HAVE_RAID=1
    command -v cryptsetup > /dev/null && export HAVE_CRYPT=1
fi

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell"
client_run() {
    local test_name="$1"
    shift
    local disk="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker

    qemu_add_drive disk_index disk_args "$TESTDIR/${disk}-1.img" disk1

    if ! grep -qF 'degraded' "$test_name"; then
        # only add disk2 if RAID is NOT degraded
        qemu_add_drive disk_index disk_args "$TESTDIR/${disk}-2.img" disk2
    fi

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE ro $client_opts " \
        -initrd "$TESTDIR"/initramfs.testing || return 1
    test_marker_check || return 1

    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    # ignore crypttab with rd.luks.crypttab=0 and RAID with rd.md=0
    client_run "$TEST_FSTYPE" "disk" "rd.auto=1 rd.luks.crypttab=0 rd.md=0" || return 1

    # LVM-THIN
    if [ -n "$USE_LVM" ]; then
        client_run "$TEST_FSTYPE" "disk-thin" "rd.auto=1 rd.luks.crypttab=0 rd.md=0" || return 1
    fi

    # ignore crypttab with rd.luks.crypttab=0
    if [ -n "$HAVE_RAID" ]; then
        client_run "raid" "raid" "rd.auto=1 rd.luks.crypttab=0" || return 1
        client_run "degraded raid" "raid" "rd.auto=1 rd.luks.crypttab=0" || return 1
    fi

    # for encrypted test run - use raid-crypt.img drives instead of raid.img drives
    if [ -n "$HAVE_CRYPT" ] && [ -n "$HAVE_RAID" ]; then
        client_run "raid crypt" "raid-crypt" "rd.auto=1 " || return 1
        client_run "degraded raid crypt" "raid-crypt" "rd.auto=1 " || return 1

        read -r LUKS_UUID < "$TESTDIR"/luksuuid
        read -r MD_UUID < "$TESTDIR"/mduuid
        client_run "degraded raid crypt" "raid-crypt" "rd.luks.uuid=$LUKS_UUID rd.md.uuid=$MD_UUID rd.md.conf=0 rd.lvm.vg=dracut" || return 1
        client_run "degraded raid crypt" "raid-crypt" "rd.luks.uuid=$LUKS_UUID rd.md.uuid=$MD_UUID rd.lvm.vg=dracut" || return 1
        client_run "degraded raid crypt" "raid-crypt" "rd.luks.uuid=$LUKS_UUID rd.md.uuid=$MD_UUID rd.lvm.lv=dracut/root" || return 1
    fi
}

test_makeroot() {
    local test_name="$1"
    shift
    local disk="$1"
    shift
    local client_opts="$*"

    echo "MAKEROOT START: $test_name"

    # Create the blank files to use as a root filesystem
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR/${disk}-1.img" disk1 1
    qemu_add_drive disk_index disk_args "$TESTDIR/${disk}-2.img" disk2 1

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot quiet console=ttyS0,115200n81 $client_opts " \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1

    echo "MAKEROOT END: $test_name [OK]"
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # pass enviroment variables to make the root filesystem
    echo "TEST_FSTYPE=${TEST_FSTYPE}" > "$TESTDIR"/overlay/env

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.

    # shellcheck disable=SC2046
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "lvm" \
        -I "grep" \
        $(if command -v mdadm > /dev/null; then echo "-a mdraid"; fi) \
        $(if command -v cryptsetup > /dev/null; then echo "-a crypt -I cryptsetup"; fi) \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; else echo "-I mkfs.${TEST_FSTYPE}"; fi) \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    # LVM
    test_makeroot "$TEST_FSTYPE" "disk" "rd.md=0 rd.luks=0" || return 1

    # LVM-THIN
    if [ -n "$USE_LVM" ]; then
        test_makeroot "$TEST_FSTYPE" "disk-thin" "rd.md=0 rd.luks=0 test.thin" || return 1
    fi

    if [ -n "$HAVE_RAID" ]; then
        test_makeroot "raid" "raid" "rd.luks=0" || return 1
    fi

    # for encrypted test run - use raid-crypt.img drives instead of raid.img drives
    if [ -n "$HAVE_CRYPT" ] && [ -n "$HAVE_RAID" ]; then
        test_makeroot "raid-crypt" "raid-crypt" " " || return 1

        eval "$(grep -F --binary-files=text -m 1 MD_UUID "$TESTDIR"/marker.img)"
        echo "$MD_UUID" > "$TESTDIR"/mduuid
        echo "ARRAY /dev/md0 level=raid1 num-devices=2 UUID=$MD_UUID" > /tmp/mdadm.conf

        eval "$(grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img)"
        echo "$ID_FS_UUID" > "$TESTDIR"/luksuuid
        echo "testluks UUID=$ID_FS_UUID /etc/key" > /tmp/crypttab
        echo -n "test" > /tmp/key
        chmod 0600 /tmp/key
    fi

    # shellcheck disable=SC2046
    test_dracut \
        -a "lvm" \
        $(if command -v mdadm > /dev/null; then echo "-a mdraid"; fi) \
        $(if command -v cryptsetup > /dev/null; then echo "-a crypt"; fi) \
        $(if [ "$TEST_FSTYPE" = "zfs" ]; then echo "-a zfs"; fi) \
        -i "/tmp/mdadm.conf" "/etc/mdadm.conf" \
        -i "./cryptroot-ask.sh" "/sbin/cryptroot-ask" \
        -i "/tmp/crypttab" "/etc/crypttab" \
        -i "/tmp/key" "/etc/key" \
        "$TESTDIR"/initramfs.testing
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

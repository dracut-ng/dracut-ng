#!/usr/bin/env bash
set -eu
# shellcheck disable=SC2034
TEST_DESCRIPTION="dracut hooks in various locations"

# Use always executed hooks for testing
hookdirs="pre-mount cmdline pre-udev pre-trigger pre-pivot cleanup"

testlog_check() {
    echo "Testing for $1 presence"
    grep -U --binary-files=binary -F -m 1 -q "$1" "$TESTDIR"/testlog.img
}

test_run() {
    local _d _h _i

    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/testlog.img testlog
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu -nic none \
        "${disk_args[@]}" \
        -append "root=LABEL=dracut $TEST_KERNEL_CMDLINE" \
        -initrd "$TESTDIR"/initramfs.testing

    echo "Testing hooks with different names in all hooks location"
    _i=0
    for _d in /var/lib/dracut/hooks /etc/dracut/hooks /lib/dracut/hooks; do
        for _h in $hookdirs; do
            testlog_check "@0$_i-$_d-$_h-difname@"
        done
        _i=$((_i + 1))
    done

    echo "Testing hooks with the same name in all hooks location: /var gets priority"
    # Same name -- only the hook in the highest priority dir gets to run.
    for _h in $hookdirs; do
        # Only the hook in /var/lib/dracut/hooks must execute
        testlog_check "@0$_i-/var/lib/dracut/hooks-$_h-samename3@"
        testlog_check "@0$_i-/etc/dracut/hooks-$_h-samename3@" || exit 1
        testlog_check "@0$_i-/lib/dracut/hooks-$_h-samename3@" || exit 1
    done

    echo "Testing hooks with the same name in /etc and /var: /etc gets priority"
    _i=$((_i + 1))
    for _h in $hookdirs; do
        # Only the hook in /etc/dracut/hooks must execute
        testlog_check "@0$_i-/etc/dracut/hooks-$_h-samename2@"
        testlog_check "@0$_i-/lib/dracut/hooks-$_h-samename2@" || exit 1
    done

    testlog_check "testhook-done"

    rm -f -- "$TESTDIR"/testlog.img
}

test_setup() {
    local _d _h _i

    # create root filesystem
    "$DRACUT" --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync "$TESTDIR"/root.img
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync "$TESTDIR"/root.img
    rm -rf "$TESTDIR"/dracut.*

    mkdir -p "$TESTDIR/overlay"
    _i=0
    # Create hooks with different names. All of them must execute.
    for _d in /var/lib/dracut/hooks /etc/dracut/hooks /lib/dracut/hooks; do
        for _h in $hookdirs; do
            mkdir -p "$TESTDIR"/overlay/"$_d"/"$_h"/
            sed "s,@REPLACEME@,0$_i-$_d-$_h-difname," testhook.sh.template > "$TESTDIR"/overlay/"$_d"/"$_h"/0"$_i"-difname.sh
        done
        _i=$((_i + 1))
    done

    # Create hooks with the same name. Only the highest priority ones must execute.
    for _d in /var/lib/dracut/hooks /etc/dracut/hooks /lib/dracut/hooks; do
        for _h in $hookdirs; do
            # Only the hook in /var/lib/dracut/hooks must execute
            sed "s,@REPLACEME@,0$_i-$_d-$_h-samename3," testhook.sh.template > "$TESTDIR"/overlay/"$_d"/"$_h"/0"$_i"-samename3.sh
        done
    done
    _i=$((_i + 1))
    for _d in /lib/dracut/hooks /etc/dracut/hooks; do
        for _h in $hookdirs; do
            # Only the hook in /etc/dracut/hooks must execute
            sed "s,@REPLACEME@,0$_i-$_d-$_h-samename2," testhook.sh.template > "$TESTDIR"/overlay/"$_d"/"$_h"/0"$_i"-samename2.sh
        done
    done

    # create initramfs
    test_dracut --keep \
        -I "dd sync" \
        -i ./lasthook.sh /var/lib/dracut/hooks/cleanup/99-lasthook.sh

    # create a separate volume for test results
    dd if=/dev/zero of="$TESTDIR"/testlog.img bs=1MiB count=1 status=none && sync "$TESTDIR"/testlog.img
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

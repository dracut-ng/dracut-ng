#!/usr/bin/env bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="Full systemd serialization/deserialization test with /usr mount"

test_check() {
    if ! type -p mkfs.btrfs &> /dev/null; then
        echo "Test needs mkfs.btrfs.. Skipping"
        return 1
    fi

    command -v systemctl &> /dev/null
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.shell rd.break"
#DEBUGOUT="quiet systemd.log_level=debug systemd.log_target=console loglevel=77  rd.info rd.debug"
client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root
    qemu_add_drive disk_index disk_args "$TESTDIR"/root_crypt.btrfs root_crypt
    qemu_add_drive disk_index disk_args "$TESTDIR"/usr.btrfs usr

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -smbios type=11,value=io.systemd.credential:key=test \
        -append "$TEST_KERNEL_CMDLINE systemd.unit=testsuite.target systemd.mask=systemd-firstboot systemd.mask=systemd-vconsole-setup root=LABEL=dracut mount.usr=LABEL=dracutusr mount.usrfstype=btrfs mount.usrflags=subvol=usr,ro $client_opts $DEBUGOUT" \
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

    # volatile mode
    client_run "volatile=overlayfs root" "systemd.volatile=overlayfs" || return 1
    client_run "volatile=state root" "systemd.volatile=state" || return 1

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    # luks
    client_run "encrypted root with rd.luks.uuid" "root=LABEL=dracut_crypt rd.luks.uuid=$ID_FS_UUID rd.luks.key=/run/credentials/@system/key" || return 1
    client_run "encrypted root with rd.luks.name" "root=/dev/mapper/crypt rd.luks.name=$ID_FS_UUID=crypt rd.luks.key=/run/credentials/@system/key" || return 1
    return 0
}

test_setup() {
    # shellcheck disable=SC2064
    trap "$(shopt -p globstar)" RETURN
    shopt -q -s globstar

    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a systemd \
        -i "${PKGLIBDIR}/modules.d/80test-root/test-init.sh" "/sbin/test-init.sh" \
        -i ./test-init.sh /sbin/test-init \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1

    mkdir -p "$TESTDIR"/overlay/source && cp -a "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.* && export initdir=$TESTDIR/overlay/source

    # setup the testsuite target
    mkdir -p "$initdir"/etc/systemd/system
    cat > "$initdir"/etc/systemd/system/testsuite.target << EOF
[Unit]
Description=Testsuite target
Requires=basic.target
After=basic.target
Conflicts=rescue.target
AllowIsolate=yes
EOF

    # setup the testsuite service
    cat > "$initdir"/etc/systemd/system/testsuite.service << EOF
[Unit]
Description=Testsuite service
After=basic.target

[Service]
ExecStart=/sbin/test-init
Type=oneshot
StandardInput=tty
StandardOutput=tty
EOF

    mkdir -p "$initdir"/etc/systemd/system/testsuite.target.wants
    ln -fs ../testsuite.service "$initdir"/etc/systemd/system/testsuite.target.wants/testsuite.service

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "btrfs crypt" \
        -I "mkfs.btrfs cryptsetup" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    # Create the blank file to use as a root filesystem
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.btrfs root 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/root_crypt.btrfs root_crypt 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/usr.btrfs usr 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1

    grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img > "$TESTDIR"/luks.uuid

    local optional_modules
    if [ -f /usr/lib/systemd/systemd-battery-check ]; then
        optional_modules="$optional_modules systemd-battery-check"
    fi
    if [ -f /usr/lib/systemd/systemd-bsod ]; then
        optional_modules="$optional_modules systemd-bsod"
    fi
    if [ -f /usr/lib/systemd/systemd-pcrextend ]; then
        optional_modules="$optional_modules systemd-pcrphase"
    fi
    test_dracut \
        -a "resume dracut-systemd systemd-ac-power systemd-coredump systemd-creds systemd-cryptsetup systemd-integritysetup systemd-ldconfig systemd-pstore systemd-repart systemd-sysext systemd-veritysetup $optional_modules" \
        --add-drivers "btrfs" \
        "$TESTDIR"/initramfs.testing

    if command -v mkinitcpio &> /dev/null; then
        find "$TESTDIR"/initrd/dracut.*/initramfs/usr/lib/systemd/system/ -printf "%f\n" | sort | uniq > systemd-dracut
        mkinitcpio -k "$KVERSION" --builddir "$TESTDIR" --save -A systemd
        find "$TESTDIR"/mkinitcpio.*/root/usr/lib/systemd/system/ -printf "%f\n" | sort | uniq > systemd-mkinitcpio

        # fail the test if mkinitcpio installs some services that dracut does not
        mkinitcpio_units=$(comm -23 systemd-mkinitcpio systemd-dracut)
        if [ -n "$mkinitcpio_units" ]; then
            printf "\n *** systemd units included in initrd from mkinitcpio but not from dracut:%s\n\n" "${mkinitcpio_units}"
            exit 1
        fi
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

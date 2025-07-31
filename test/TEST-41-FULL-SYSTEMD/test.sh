#!/usr/bin/env bash
set -eu

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
    local smbios="$2"
    shift 2
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
        "${disk_args[@]}" ${smbios:+-smbios "${smbios}"} \
        -append "$TEST_KERNEL_CMDLINE mount.usr=LABEL=dracutusr mount.usrflags=subvol=usr $client_opts ${DEBUGOUT-}" \
        -initrd "$TESTDIR"/initramfs.testing

    if ! test_marker_check; then
        echo "CLIENT TEST END: $test_name [FAILED]"
        return 1
    fi
    echo "CLIENT TEST END: $test_name [OK]"
}

test_run() {
    # mask services that require rw
    client_run "readonly root" "" "ro systemd.mask=systemd-sysusers systemd.mask=systemd-timesyncd systemd.mask=systemd-resolved"

    client_run "writeable root" "" "rw"

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    if "$testdir"/run-qemu --supports -smbios; then
        # luks
        client_run "encrypted root with rd.luks.uuid" "type=11,value=io.systemd.credential:key=test" \
            "rw root=LABEL=dracut_crypt rd.luks.uuid=$ID_FS_UUID rd.luks.key=/run/credentials/@system/key"
        client_run "encrypted root with rd.luks.name" "type=11,value=io.systemd.credential:key=test" \
            "rw root=/dev/mapper/crypt rd.luks.name=$ID_FS_UUID=crypt rd.luks.key=/run/credentials/@system/key"
    else
        echo "CLIENT TEST: encrypted root with rd.luks.uuid [SKIPPED]"
        echo "CLIENT TEST: encrypted root with rd.luks.name [SKIPPED]"
    fi
    return 0
}

test_setup() {
    # shellcheck disable=SC2064
    trap "$(shopt -p globstar)" RETURN
    shopt -q -s globstar

    local dracut_modules="resume systemd-udevd systemd-journald systemd-tmpfiles systemd-cryptsetup systemd-emergency systemd-ac-power systemd-coredump systemd-creds systemd-integritysetup systemd-ldconfig systemd-pstore systemd-repart systemd-sysext systemd-veritysetup systemd-hostnamed systemd-timedated"

    # TODO - this workaround should not be needed and should be removed
    if [ -f /usr/bin/dbus-broker ]; then
        dracut_modules="$dracut_modules dbus-broker"
    else
        dracut_modules="$dracut_modules dbus-daemon"
    fi

    if [ -f /usr/lib/systemd/systemd-networkd ] && [ -e "${PKGLIBDIR}/modules.d/00systemd-network-management/module-setup.sh" ]; then
        dracut_modules="$dracut_modules systemd-network-management"
    fi

    if [ -f /usr/lib/systemd/systemd-battery-check ]; then
        dracut_modules="$dracut_modules systemd-battery-check"
    fi
    if [ -f /usr/lib/systemd/systemd-bsod ]; then
        dracut_modules="$dracut_modules systemd-bsod"
    fi
    if [ -f /usr/lib/systemd/systemd-pcrextend ]; then
        dracut_modules="$dracut_modules systemd-pcrphase"
    fi
    if [ -f /usr/lib/systemd/systemd-portabled ]; then
        dracut_modules="$dracut_modules systemd-portabled"
    fi

    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a "$dracut_modules" \
        -f "$TESTDIR"/initramfs.root "$KVERSION"

    KVERSION=$(determine_kernel_version "$TESTDIR"/initramfs.root)

    mkdir -p "$TESTDIR"/overlay/source && cp -a "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "btrfs crypt" \
        -I "mkfs.btrfs cryptsetup" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION"

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
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created

    grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img > "$TESTDIR"/luks.uuid

    # force add all available dracut modules that are dependent on systemd
    test_dracut \
        -a "dracut-systemd $dracut_modules" \
        --add-drivers "btrfs"

    # verify that systemd-coredump user exists generated by systemd-sysuser
    if ! grep -q '^systemd-coredump:' "$TESTDIR"/initrd/dracut.*/initramfs/etc/passwd; then
        # fail the test
        echo "systemd-coredump user is not present in /etc/passwd"
        rm "$TESTDIR"/initramfs.testing
        exit 1
    fi

    if command -v mkosi-initrd &> /dev/null; then
        mkosi-initrd --kernel-version "$KVERSION" -t directory -o mkosi -O "$TESTDIR"

        find "$TESTDIR"/mkosi/usr/lib/systemd/system/initrd.target.wants/ -printf "%f\n" | sort | uniq > systemd-mkosi
        find "$TESTDIR"/initrd/dracut.*/initramfs/usr/lib/systemd/system/initrd.target.wants/ -printf "%f\n" | sort | uniq > systemd-dracut

        # fail the test if mkosi installs some services that dracut does not
        mkosi_units=$(comm -23 systemd-mkosi systemd-dracut)

        if [ -n "$mkosi_units" ]; then
            printf "\n *** systemd units included in initrd from mkosi-initrd but not from dracut:%s\n\n" "${mkosi_units}"
            exit 1
        fi
    fi

    if command -v mkinitcpio &> /dev/null; then
        mkinitcpio -k "$KVERSION" --builddir "$TESTDIR" --save -A systemd

        find "$TESTDIR"/mkinitcpio.*/root/usr/lib/systemd/system/ -printf "%f\n" | sort | uniq > systemd-mkinitcpio
        find "$TESTDIR"/initrd/dracut.*/initramfs/usr/lib/systemd/system/ -printf "%f\n" | sort | uniq > systemd-dracut

        # fail the test if mkinitcpio installs some services that dracut does not
        mkinitcpio_units=$(comm -23 systemd-mkinitcpio systemd-dracut)
        if [ -n "$mkinitcpio_units" ]; then
            printf "\n *** systemd units included in initrd from mkinitcpio but not from dracut:%s\n\n" "${mkinitcpio_units}"
            exit 1
        fi

        # verify that in this configuration, dracut does not modify any native systemd service files and ensures compatibility with mkinitcpio
        (cd "$TESTDIR"/mkinitcpio.*/root/usr/lib/systemd/system/ && find . -type f > /tmp/systemd-mkinitcpio)

        while read -r unit; do
            if ! diff -q "$TESTDIR"/mkinitcpio.*/root/usr/lib/systemd/system/"$unit" "$TESTDIR"/initrd/dracut.*/initramfs/usr/lib/systemd/system/"$unit"; then
                exit 1
            fi
        done < /tmp/systemd-mkinitcpio

    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

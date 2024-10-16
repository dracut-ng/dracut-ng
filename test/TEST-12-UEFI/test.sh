#!/usr/bin/env bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="UEFI boot"

test_check() {
    [[ -n "$(ovmf_code)" ]]
}

client_run() {
    local test_name="$1"
    shift
    local client_opts="$*"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=1
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/squashfs.img root

    test_marker_reset
    "$testdir"/run-qemu "${disk_args[@]}" -net none \
        -drive file=fat:rw:"$TESTDIR"/ESP,format=vvfat,label=EFI \
        -global driver=cfi.pflash01,property=secure,value=on \
        -smbios type=11,value=io.systemd.stub.kernel-cmdline-extra="$client_opts" \
        -drive if=pflash,format=raw,unit=0,file="$(ovmf_code)",readonly=on
    test_marker_check || return 1
}

test_run() {
    client_run "readonly root" "ro rd.skipfsck" || return 1
}

test_setup() {
    # Create what will eventually be our root filesystem
    "$DRACUT" -N -l --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        "$TESTDIR"/tmp-initramfs.root "$KVERSION" || return 1

    mksquashfs "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/squashfs.img -quiet -no-progress

    mkdir -p "$TESTDIR"/ESP/EFI/BOOT "$TESTDIR"/dracut.conf.d

    # test with the reference uki config when systemd is available
    if command -v systemctl &> /dev/null; then
        cp "${basedir}"/dracut.conf.d/uki-virt/* "$TESTDIR"/dracut.conf.d/
    fi

    if command -v ukify &> /dev/null; then
        echo "Using ukify to create UKI"
        test_dracut --no-uefi \
            --drivers 'squashfs' \
            "$TESTDIR"/initramfs.testing

        ukify build \
            --linux="$VMLINUZ" \
            --initrd="$TESTDIR"/initramfs.testing \
            --cmdline='root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root' \
            --output="$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi
    else
        echo "Using dracut to create UKI"
        test_dracut \
            --kernel-cmdline 'root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root' \
            --drivers 'squashfs' \
            --uefi \
            "$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi
    fi
}

test_cleanup() {
    return 0
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

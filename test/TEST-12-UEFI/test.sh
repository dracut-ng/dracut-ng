#!/usr/bin/env bash
set -e

# shellcheck disable=SC2034
TEST_DESCRIPTION="UEFI boot (ukify, kernel-install)"

test_check() {
    if ! type -p mksquashfs &> /dev/null; then
        echo "Test needs mksquashfs... Skipping"
        return 1
    fi

    local arch=${DRACUT_ARCH:-$(uname -m)}
    if [[ ! ${arch} =~ ^(x86_64|i.86|aarch64|riscv64)$ ]]; then
        echo "Architecture '$arch' not supported to create a UEFI executable... Skipping" >&2
        return 1
    fi

    [[ -n "$(ovmf_code)" ]]
}

client_run() {
    local test_name="$1"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=1
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/squashfs.img root

    test_marker_reset
    "$testdir"/run-qemu "${disk_args[@]}" -net none \
        -drive file=fat:rw:"$TESTDIR"/ESP,format=vvfat,label=EFI \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,unit=0,file="$(ovmf_code)",readonly=on
    test_marker_check
}

test_run() {
    client_run "UEFI with UKI and squashfs root"
}

test_setup() {
    # Create what will eventually be our root filesystem
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        "$TESTDIR"/tmp-initramfs.root "$KVERSION"

    mksquashfs "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/squashfs.img -quiet -no-progress

    mkdir -p "$TESTDIR"/ESP/EFI/BOOT "$TESTDIR"/dracut.conf.d

    # This is the preferred way to build uki with dracut on a systenmd based system
    # Currently this only works in a few distributions and architectures, but it is here
    # for reference
    if command -v systemd-detect-virt &> /dev/null && systemd-detect-virt -c &> /dev/null \
        && command -v kernel-install &> /dev/null \
        && command -v systemctl &> /dev/null \
        && command -v ukify &> /dev/null \
        && [[ $(kernel-install --version | grep -oP '(?<=systemd )\d+') -gt 254 ]]; then

        echo "Using ukify via kernel-install to create UKI"

        mkdir -p /etc/kernel

        {
            echo 'initrd_generator=dracut'
            echo 'layout=uki'
            echo 'uki_generator=ukify'
        } >> /etc/kernel/install.conf

        echo "$TEST_KERNEL_CMDLINE root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root" >> /etc/kernel/cmdline

        # enable test dracut config
        cp "${basedir}"/dracut.conf.d/test/* "${basedir}"/dracut.conf.d/uki-virt/* /usr/lib/dracut/dracut.conf.d/
        echo 'add_drivers+=" squashfs "' >> /usr/lib/dracut/dracut.conf.d/extra.conf

        # using kernell-install to invoke dracut
        mkdir -p "$BOOT_ROOT/$TOKEN/$KVERSION" "$BOOT_ROOT/loader/entries"
        kernel-install add-all

        mv "$TESTDIR"/EFI/Linux/*.efi "$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi

        return 0
    fi

    # test with the reference uki config when systemd is available
    if command -v systemctl &> /dev/null; then
        cp "${basedir}"/dracut.conf.d/uki-virt/* "$TESTDIR"/dracut.conf.d/
    fi

    if command -v ukify &> /dev/null; then
        echo "Using ukify to create UKI"
        test_dracut --no-uefi \
            --drivers 'squashfs'

        ukify build \
            --linux="$VMLINUZ" \
            --initrd="$TESTDIR"/initramfs.testing \
            --cmdline="$TEST_KERNEL_CMDLINE root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root" \
            --output="$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi
    else
        echo "Using dracut to create UKI"
        test_dracut \
            --kernel-cmdline "$TEST_KERNEL_CMDLINE root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root" \
            --drivers 'squashfs' \
            --uefi \
            "$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

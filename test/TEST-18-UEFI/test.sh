#!/bin/bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="UEFI boot"

ovmf_code() {
    for path in \
        "/usr/share/OVMF/OVMF_CODE.fd" \
        "/usr/share/OVMF/OVMF_CODE_4M.fd" \
        "/usr/share/edk2/x64/OVMF_CODE.fd" \
        "/usr/share/edk2-ovmf/OVMF_CODE.fd" \
        "/usr/share/qemu/ovmf-x86_64-4m.bin"; do
        [[ -s $path ]] && echo -n "$path" && return
    done
}

test_check() {
    [[ -n "$(ovmf_code)" ]]
}

VMLINUZ="/lib/modules/${KVERSION}/vmlinuz"
if ! [ -f "$VMLINUZ" ]; then
    VMLINUZ="/lib/modules/${KVERSION}/vmlinux"
fi

if ! [ -f "$VMLINUZ" ]; then
    [[ -f /etc/machine-id ]] && read -r MACHINE_ID < /etc/machine-id

    if [[ $MACHINE_ID ]] && { [[ -d /boot/${MACHINE_ID} ]] || [[ -L /boot/${MACHINE_ID} ]]; }; then
        VMLINUZ="/boot/${MACHINE_ID}/$KVERSION/linux"
    elif [ -f "/boot/vmlinuz-${KVERSION}" ]; then
        VMLINUZ="/boot/vmlinuz-${KVERSION}"
    elif [ -f "/boot/vmlinux-${KVERSION}" ]; then
        VMLINUZ="/boot/vmlinux-${KVERSION}"
    elif [ -f "/boot/kernel-${KVERSION}" ]; then
        VMLINUZ="/boot/kernel-${KVERSION}"
    else
        echo "Could not find a Linux kernel version $KVERSION to test with!" >&2
        echo "Please install linux." >&2
        exit 1
    fi
fi

test_run() {
    declare -a disk_args=()
    declare -i disk_index=1
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/squashfs.img root

    test_marker_reset
    "$testdir"/run-qemu "${disk_args[@]}" -net none \
        -drive file=fat:rw:"$TESTDIR"/ESP,format=vvfat,label=EFI \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,unit=0,file="$(ovmf_code)",readonly=on
    test_marker_check || return 1
}

test_setup() {
    # Create what will eventually be our root filesystem
    "$DRACUT" -N -l --keep --tmpdir "$TESTDIR" \
        -m "test-root" \
        "$TESTDIR"/tmp-initramfs.root "$KVERSION" || return 1

    mkdir -p "$TESTDIR"/dracut.*/initramfs/proc
    mksquashfs "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/squashfs.img -quiet -no-progress

    mkdir -p "$TESTDIR"/ESP/EFI/BOOT /tmp/dracut.conf.d

    # test with the reference uki config when systemd is available
    if command -v systemctl &> /dev/null; then
        cp "${basedir}/dracut.conf.d/50-uki-virt.conf.example" /tmp/dracut.conf.d/50-uki-virt.conf
    fi

    if command -v ukify &> /dev/null; then
        echo "Using ukify to create UKI"
        test_dracut --no-uefi \
            --drivers 'squashfs' \
            "$TESTDIR"/initramfs.testing

        ukify build \
            --linux="$VMLINUZ" \
            --initrd="$TESTDIR"/initramfs.testing \
            --cmdline='root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root ro rd.skipfsck rootfstype=squashfs' \
            --output="$TESTDIR"/ESP/EFI/BOOT/BOOTX64.efi
    else
        echo "Using dracut to create UKI"
        test_dracut \
            --kernel-cmdline 'root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_root ro rd.skipfsck rootfstype=squashfs' \
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

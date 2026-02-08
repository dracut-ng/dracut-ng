#!/bin/bash

is_qemu_virtualized() {
    # 0 if a QEMU/KVM like VM virtualization environment was detected
    # 1 if a QEMU/KVM like VM virtualization environment could not be detected (including if an error was encountered)

    # do not consult /sys and do not detect virt environment in non-hostonly mode
    ! [[ ${hostonly-} ]] && return 1

    if type -P systemd-detect-virt > /dev/null 2>&1; then
        if ! vm=$(systemd-detect-virt --vm 2> /dev/null); then
            return 1
        fi
        [[ $vm == "qemu" ]] && return 0
        [[ $vm == "kvm" ]] && return 0
        [[ $vm == "bochs" ]] && return 0
    fi

    for i in /sys/class/dmi/id/*_vendor; do
        [[ -f $i ]] || continue
        read -r vendor < "$i"
        [[ $vendor == "QEMU" ]] && return 0
        [[ $vendor == "Red Hat" ]] && return 0
        [[ $vendor == "Bochs" ]] && return 0
    done
    return 1
}

# called by dracut
check() {
    is_qemu_virtualized && return 0

    if [[ $hostonly ]] || [[ $mount_needs ]]; then
        return 255
    fi

    return 0
}

# called by dracut
installkernel() {
    # qemu specific modules
    hostonly='' instmods \
        ata_piix ata_generic pata_acpi cdrom sr_mod sd_mod ahci \
        virtio_blk virtio virtio_crypto virtio_ring virtio_pci \
        virtio_scsi virtio_console virtio_rng virtio_mem \
        spapr-vscsi \
        qemu_fw_cfg \
        efi_secret
}

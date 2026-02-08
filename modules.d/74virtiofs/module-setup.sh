#!/bin/bash

# called by dracut
check() {
    if [[ $hostonly_mode != "strict" ]] && dracut_module_included "qemu"; then
        return 0
    fi

    [[ $hostonly ]] || [[ $mount_needs ]] && {
        for fs in "${host_fs_types[@]}"; do
            [[ $fs == "virtiofs" ]] && return 0
        done
        return 255
    }

    return 0
}

# called by dracut
depends() {
    echo base
}

# called by dracut
installkernel() {
    hostonly='' instmods virtiofs virtio_pci
}

# called by dracut
install() {
    inst_hook cmdline 95 "$moddir/parse-virtiofs.sh"
    inst_hook pre-mount 99 "$moddir/mount-virtiofs.sh"
}

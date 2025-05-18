#!/bin/bash

# called by dracut
check() {
    is_qemu_virtualized && return 0

    if [[ $hostonly_mode == "strict" ]] || [[ $mount_needs ]]; then
        return 255
    fi

    return 0
}

# called by dracut
installkernel() {
    # qemu specific modules
    hostonly=$(optional_hostonly) instmods virtio_net e1000 8139cp pcnet32 e100 ne2k_pci
}

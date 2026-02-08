#!/bin/bash

# called by dracut
check() {
    if [[ $hostonly_mode != "strict" ]] && dracut_module_included "net-lib" \
        && dracut_module_included "qemu"; then
        return 0
    fi

    if [[ $hostonly ]] || [[ $mount_needs ]]; then
        return 255
    fi

    return 0
}

# called by dracut
installkernel() {
    # qemu specific modules
    hostonly=$(optional_hostonly) instmods virtio_net e1000 8139cp pcnet32 e100 ne2k_pci
}

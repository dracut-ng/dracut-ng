#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "base debug qemu"
}

installkernel() {
    instmods \
        ata_piix \
        ext4 \
        i6300esb \
        ide-gd_mod \
        piix \
        sd_mod \
        virtio_pci \
        virtio_scsi
}

install() {
    # do not compress, do not strip
    export compress="cat"
    export do_strip="no"
    export do_hardlink="no"
    export early_microcode="no"
    export hostonly_cmdline="no"

    inst poweroff
    inst_hook shutdown-emergency 000 "$moddir/hard-off.sh"
    inst_hook emergency 000 "$moddir/hard-off.sh"
}

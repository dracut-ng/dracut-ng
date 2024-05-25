#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "dash rootfs-block kernel-modules qemu"
}

installkernel() {
    instmods piix ide-gd_mod ata_piix ext4 sd_mod
}

install() {
    # do not compress, do not strip
    export compress="cat"
    export do_strip="no"
    export do_hardlink="no"
    export early_microcode="no"
    export hostonly_cmdline="no"

    inst_multiple poweroff cp umount sync dd mkfs.ext4
    inst_hook initqueue/finished 01 "$moddir/finished-false.sh"
}

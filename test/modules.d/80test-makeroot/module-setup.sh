#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "rootfs-block kernel-modules qemu"
}

installkernel() {
    hostonly='' instmods piix ide-gd_mod ata_piix ext4 sd_mod
}

install() {
    inst_multiple poweroff cp umount sync mkfs.ext4

    # prefer the coreutils version of dd over the busybox version for testing
    inst /bin/dd /usr/sbin/dd

    inst_hook initqueue/finished 01 "$moddir/finished-false.sh"
}

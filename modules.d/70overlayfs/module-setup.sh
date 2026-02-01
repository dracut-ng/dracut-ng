#!/bin/bash

check() {
    require_kernel_modules overlay || return 1
    return 255
}

depends() {
    echo base
}

installkernel() {
    hostonly="" instmods overlay dm_mod dm_crypt
}

install() {
    inst_hook pre-mount 01 "$moddir/prepare-overlayfs.sh"
    inst_hook mount 01 "$moddir/mount-overlayfs.sh"       # overlay on top of block device
    inst_hook pre-pivot 00 "$moddir/prepare-overlayfs.sh" # prepare for network root (e.g. nfs)
    inst_hook pre-pivot 10 "$moddir/mount-overlayfs.sh"   # overlay on top of network device

    inst_simple "$moddir/overlayfs-crypt-lib.sh" "/lib/overlayfs-crypt-lib.sh"
    inst_multiple -o cryptsetup wipefs mkfs.ext4 mkfs.ext3 mkfs.ext2 sha512sum mktemp chmod readlink timeout
}

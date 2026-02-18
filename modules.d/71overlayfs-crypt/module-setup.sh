#!/bin/bash

check() {
    require_any_binary cryptsetup || return 1
    return 255
}

depends() {
    echo overlayfs
}

installkernel() {
    hostonly="" instmods dm_mod dm_crypt
}

install() {
    inst_hook pre-mount 02 "$moddir/prepare-overlayfs-crypt.sh"
    inst_hook pre-pivot 01 "$moddir/prepare-overlayfs-crypt.sh"

    inst_simple "$moddir/overlayfs-crypt-lib.sh" "/lib/overlayfs-crypt-lib.sh"
    inst_multiple cryptsetup wipefs mkfs.ext4 mkfs.ext3 mkfs.ext2 sha512sum mktemp chmod readlink timeout
}

#!/bin/bash

check() {
    require_binaries memdiskfind || return 1
    return 255
}

installkernel() {
    hostonly='' instmods \
        "=drivers/mtd/devices/phram" \
        "=drivers/mtd/mtdblock"
}

install() {
    inst memdiskfind
    inst_hook cmdline 30 "$moddir/memdisk.sh"
}

#!/bin/bash

# called by dracut
check() {
    # a live host-only image doesn't really make a lot of sense
    [[ $hostonly ]] && return 1
    return 255
}

# called by dracut
depends() {
    echo rootfs-block
    return 0
}

# called by dracut
installkernel() {
    instmods loop iso9660
}

# called by dracut
install() {
    inst_multiple umount losetup rmdir
    inst_hook cmdline 31 "$moddir/parse-iso-scan.sh"
    inst_script "$moddir/iso-scan.sh" "/sbin/iso-scan"
    dracut_need_initqueue
}

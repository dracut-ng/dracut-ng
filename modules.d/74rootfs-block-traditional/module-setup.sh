#!/bin/bash

# Prerequisite check(s) for module.
check() {
    if dracut_module_included "systemd"; then
        return 255
    else
        return 0
    fi
}

# called by dracut
depends() {
    echo rootfs-block
    return 0
}

# called by dracut
install() {
    if ! dracut_module_included "systemd"; then
        inst_hook cmdline 95 "$moddir/parse-block.sh"
        inst_hook pre-udev 30 "$moddir/block-genrules.sh"
        inst_hook mount 99 "$moddir/mount-root.sh"
    fi
}

#!/bin/bash

# called by dracut
check() {
    [[ -f "${dracutsysrootdir-}/etc/fstab.initramfs" ]]
}

# called by dracut
install() {
    inst_simple /etc/fstab.initramfs /etc/fstab
}

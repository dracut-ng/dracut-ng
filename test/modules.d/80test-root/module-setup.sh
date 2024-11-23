#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    if [[ $V == "2" ]]; then
        echo debug
    fi

    return 0
}

install() {
    inst_simple /etc/os-release

    inst_multiple mkdir ln dd stty mount poweroff umount setsid sync cat grep

    for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
        [ -f "${_terminfodir}/l/linux" ] && break
    done
    inst_multiple -o "${_terminfodir}/l/linux"

    inst_script "$moddir/test-init.sh" "/sbin/init"

    inst_multiple -o plymouth
}

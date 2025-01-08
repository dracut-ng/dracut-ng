#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    local deps
    deps="terminfo"

    if [[ $V == "2" ]]; then
        deps+=" debug"
    fi

    echo "$deps"
    return 0
}

install() {
    inst_simple /etc/os-release

    inst_multiple mkdir ln dd mount poweroff umount setsid sync cat grep

    inst_script "$moddir/test-init.sh" "/sbin/init"
}

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

    if dracut_module_included "systemd"; then
        inst_simple "$moddir/testsuite.target" "${systemdsystemunitdir}/testsuite.target"
        inst_simple "$moddir/testsuite.service" "${systemdsystemunitdir}/testsuite.service"
        $SYSTEMCTL -q --root "$initdir" add-wants testsuite.target "testsuite.service"
        ln_r "${systemdsystemunitdir}/testsuite.target" "${systemdsystemunitdir}/default.target"
    fi
}

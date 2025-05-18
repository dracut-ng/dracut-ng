#!/bin/bash

check() {
    # If you need to use rd.memdebug>=4, please install all the required binary dependencies
    require_binaries \
        pgrep \
        pkill \
        memstrack \
        || return 1

    return 0
}

depends() {
    echo systemd
    return 0
}

install() {
    inst_multiple pgrep pkill nohup
    inst "/bin/memstrack" "/bin/memstrack"

    inst "$moddir/memstrack-start.sh" "/bin/memstrack-start"
    inst_hook cleanup 99 "$moddir/memstrack-report.sh"

    inst "$moddir/memstrack.service" "$systemdsystemunitdir/memstrack.service"

    $SYSTEMCTL -q --root "$initdir" add-wants initrd.target memstrack.service
}

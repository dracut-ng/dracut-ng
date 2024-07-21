#!/bin/bash

# called by dracut
check() {
    require_binaries busybox || return 1

    return 255
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    local _busybox
    _busybox=$(find_binary busybox)
    inst "$_busybox" /usr/bin/busybox
    $_busybox --install -s /bin/
}

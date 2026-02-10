#!/bin/bash

check() {
    return 255
}

# called by dracut
depends() {
    echo rootfs-block initqueue
}

# called by dracut
install() {
    inst_hook initqueue/timeout 99 "$moddir/rootfallback.sh"
}

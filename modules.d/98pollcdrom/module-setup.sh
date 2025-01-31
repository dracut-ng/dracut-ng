#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    echo initqueue
    return 0
}

# called by dracut
install() {
    inst_hook initqueue/settled 99 "$moddir/pollcdrom.sh"
}

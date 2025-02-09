#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
install() {
    inst_hook initqueue/settled 99 "$moddir/pollcdrom.sh"
}

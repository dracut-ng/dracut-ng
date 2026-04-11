#!/bin/bash

check() {
    return 255
}

# called by dracut
install() {
    inst_multiple -o stty
    inst_simple "$moddir/crypt-lib.sh" "/lib/dracut-crypt-lib.sh"
}

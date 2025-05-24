#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "base debug kernel-modules qemu watchdog"
}

# testsuite assumes ext4 for convenience
installkernel() {
    hostonly='' instmods ext4
}

install() {
    inst poweroff
    inst_hook shutdown-emergency 000 "$moddir/hard-off.sh"
    inst_hook emergency 000 "$moddir/hard-off.sh"
}

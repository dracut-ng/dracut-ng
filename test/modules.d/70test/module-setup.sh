#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "base debug qemu watchdog kernel-modules"
}

# testsuite assumes ext4 for convenience
installkernel() {
    hostonly='' instmods \
        ext4
}

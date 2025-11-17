#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    echo "rootfs-block kernel-modules qemu initqueue"
}

install() {
    inst_multiple cp umount sync mkfs.ext4

    # prefer the coreutils version of dd over the busybox version for testing
    if [ -x /usr/bin/gnudd ]; then
        # use GNU dd instead of uutil's dd due to https://launchpad.net/bugs/2129037
        inst /usr/bin/gnudd /usr/sbin/dd
    else
        inst /bin/dd /usr/sbin/dd
    fi

    inst_hook initqueue/finished 01 "$moddir/finished-false.sh"
}

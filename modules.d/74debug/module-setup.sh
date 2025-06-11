#!/bin/bash

# called by dracut
check() {
    # do not add this module by default
    return 255
}

# called by dracut
install() {
    inst_multiple -o \
        cat \
        chroot \
        cp \
        dd \
        df \
        du \
        e2fsck \
        findmnt \
        find \
        free \
        fsck \
        fsck.ext2 \
        fsck.ext3 \
        fsck.ext4 \
        fsck.ext4dev \
        fsck.f2fs \
        fsck.vfat \
        grep \
        hostname \
        less \
        ls \
        lsblk \
        mkdir \
        more \
        netstat \
        ping \
        ping6 \
        ps \
        rm \
        rpcinfo \
        scp \
        showmount \
        ssh \
        strace \
        systemd-analyze \
        tcpdump \
        vi

    grep '^tcpdump:' "${dracutsysrootdir-}"/etc/passwd 2> /dev/null >> "$initdir/etc/passwd"
}

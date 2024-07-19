#!/bin/bash

# called by dracut
check() {
    # if we don't have btrfs installed on the host system,
    # no point in trying to support it in the initramfs.
    require_binaries btrfs || return 1

    [[ $hostonly ]] || [[ $mount_needs ]] && {
        for fs in "${host_fs_types[@]}"; do
            [[ $fs == "btrfs" ]] && return 0
        done
        return 255
    }

    return 0
}

# called by dracut
depends() {
    echo udev-rules
    return 0
}

# called by dracut
cmdline() {
    # Hack for slow machines
    # see https://github.com/dracutdevs/dracut/issues/658
    printf " rd.driver.pre=btrfs"
}

# called by dracut
installkernel() {
    instmods btrfs
    printf "%s\n" "$(cmdline)" > "${initdir}/etc/cmdline.d/00-btrfs.conf"
}

# called by dracut
install() {
    inst_rules 64-btrfs-dm.rules
    inst_multiple -o btrfsck
    inst "$(command -v btrfs)" /sbin/btrfs
}

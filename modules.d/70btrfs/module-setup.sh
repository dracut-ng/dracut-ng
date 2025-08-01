#!/bin/bash

# called by dracut
check() {
    # if we don't have btrfs installed on the host system,
    # no point in trying to support it in the initramfs.
    require_binaries btrfs || return 1

    [[ $hostonly_mode == "strict" ]] || [[ $mount_needs ]] && {
        for fs in "${host_fs_types[@]}"; do
            [[ $fs == "btrfs" ]] && return 0
        done
        return 255
    }

    return 0
}

# called by dracut
depends() {
    echo udev-rules initqueue
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
    hostonly='' instmods btrfs
}

# called by dracut
install() {
    if ! inst_rules 64-btrfs.rules; then
        inst_rules "$moddir/80-btrfs.rules"
        case "$(btrfs --help)" in
            *device\ ready*)
                inst_script "$moddir/btrfs_device_ready.sh" /sbin/btrfs_finished
                ;;
            *)
                inst_script "$moddir/btrfs_finished.sh" /sbin/btrfs_finished
                ;;
        esac
    else
        inst_rules 64-btrfs-dm.rules
    fi

    if ! dracut_module_included "systemd"; then
        inst_hook initqueue/timeout 10 "$moddir/btrfs_timeout.sh"
    fi

    inst_multiple -o btrfsck btrfs-zero-log btrfstune
    inst btrfs /sbin/btrfs

    if [[ $hostonly_cmdline == "yes" ]]; then
        printf "%s\n" "$(cmdline)" > "${initdir}/etc/cmdline.d/00-btrfs.conf"
    fi
}

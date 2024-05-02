#!/bin/bash

# called by dracut
check() {
    local fs
    # if cryptsetup is not installed, then we cannot support encrypted devices.
    require_any_binary "$systemdutildir"/systemd-cryptsetup || return 1

    [[ $hostonly ]] || [[ $mount_needs ]] && {
        for fs in "${host_fs_types[@]}"; do
            [[ $fs == "crypto_LUKS" ]] && return 0
        done
        return 255
    }

    return 0
}

# called by dracut
depends() {
    echo dm rootfs-block crypt systemd-ask-password
    return 0
}

# called by dracut
install() {
    # the cryptsetup targets are already pulled in by 00systemd, but not
    # the enablement symlinks
    inst_multiple -o \
        "$tmpfilesdir"/cryptsetup.conf \
        "$systemdutildir"/system-generators/systemd-cryptsetup-generator \
        "$systemdutildir"/systemd-cryptsetup \
        "$systemdsystemunitdir"/cryptsetup.target \
        "$systemdsystemunitdir"/sysinit.target.wants/cryptsetup.target \
        "$systemdsystemunitdir"/remote-cryptsetup.target \
        "$systemdsystemunitdir"/initrd-root-device.target.wants/remote-cryptsetup.target
}

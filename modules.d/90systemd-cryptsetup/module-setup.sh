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
    local deps
    deps="dm rootfs-block crypt systemd-ask-password"
    if [[ $hostonly && -f "$dracutsysrootdir"/etc/crypttab ]]; then
        if grep -q -e "fido2-device=" -e "fido2-cid=" "$dracutsysrootdir"/etc/crypttab; then
            deps+=" fido2"
        fi
        if grep -q "pkcs11-uri" "$dracutsysrootdir"/etc/crypttab; then
            deps+=" pkcs11"
        fi
        if grep -q "tpm2-device=" "$dracutsysrootdir"/etc/crypttab; then
            deps+=" tpm2-tss"
        fi
    fi
    echo "$deps"
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

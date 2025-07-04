#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Prerequisite check(s) for module.
check() {

    # If the binary(s) requirements are not fulfilled the module can't be installed.
    require_binaries systemd-sysext || return 1

    # Return 255 to only include the module, if another module requires it.
    return 255

}

# Module dependency requirements.
depends() {

    # This module has external dependency on other module(s).
    echo systemd
    # Return 0 to include the dependent module(s) in the initramfs.
    return 0

}

# Install kernel module(s).
installkernel() {
    hostonly=$(optional_hostonly) instmods -s erofs
    hostonly='' instmods loop
}

# Install the required file(s) and directories for the module in the initramfs.
install() {

    local _suffix=

    # systemd >= v258
    [[ -e "${dracutsysrootdir-}$systemdsystemunitdir"/systemd-sysext-initrd.service ]] && _suffix="-initrd"

    # It's intended to work only with raw binary disk images contained in
    # regular files, but not with directory trees.

    inst_multiple -o \
        "/usr/lib/confexts/*.raw" \
        "/usr/lib/extension-release.d/extension-release.*" \
        "$systemdsystemunitdir"/systemd-confext${_suffix}.service \
        "$systemdsystemunitdir/systemd-confext${_suffix}.service.d/*.conf" \
        "$systemdsystemunitdir"/systemd-sysext${_suffix}.service \
        "$systemdsystemunitdir/systemd-sysext${_suffix}.service.d/*.conf" \
        systemd-confext systemd-sysext

    # Enable systemd type unit(s)
    for i in \
        systemd-confext.service \
        systemd-sysext.service; do
        $SYSTEMCTL -q --root "$initdir" enable "$i"
    done

    # Install the hosts local user configurations if enabled.
    if [[ ${hostonly-} ]]; then
        inst_multiple -H -o \
            "/etc/extensions/*.raw" \
            "/etc/extension-release.d/extension-release.*" \
            "/var/lib/confexts/*.raw" \
            "/var/lib/extensions/*.raw" \
            "$systemdsystemconfdir"/systemd-confext${_suffix}.service \
            "$systemdsystemconfdir/systemd-confext${_suffix}.service.d/*.conf" \
            "$systemdsystemconfdir"/systemd-sysext${_suffix}.service \
            "$systemdsystemconfdir/systemd-sysext${_suffix}.service.d/*.conf"
    fi

}

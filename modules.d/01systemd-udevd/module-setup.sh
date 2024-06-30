#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Prerequisite check(s) for module.
check() {

    # If the binary(s) requirements are not fulfilled the module can't be installed.
    require_binaries \
        udevadm \
        "$systemdutildir"/systemd-udevd \
        || return 1

    # Return 255 to only include the module, if another module requires it.
    return 255

}

# Module dependency requirements.
depends() {

    # This module has external dependency on other module(s).
    echo udev-rules systemd systemd-sysctl
    # Return 0 to include the dependent module(s) in the initramfs.
    return 0

}

# Install the required file(s) and directories for the module in the initramfs.
install() {

    inst_multiple -o \
        "$udevrulesdir"/99-systemd.rules \
        "$systemdutildir"/systemd-udevd \
        "$systemdsystemunitdir"/systemd-udevd.service \
        "$systemdsystemunitdir/systemd-udevd.service.d/*.conf" \
        "$systemdsystemunitdir"/systemd-udev-trigger.service \
        "$systemdsystemunitdir/systemd-udev-trigger.service.d/*.conf" \
        "$systemdsystemunitdir"/systemd-udev-settle.service \
        "$systemdsystemunitdir/systemd-udev-settle.service.d/*.conf" \
        "$systemdsystemunitdir"/systemd-udevd-control.socket \
        "$systemdsystemunitdir"/systemd-udevd-kernel.socket \
        "$systemdsystemunitdir"/sockets.target.wants/systemd-udevd-control.socket \
        "$systemdsystemunitdir"/sockets.target.wants/systemd-udevd-kernel.socket \
        "$systemdsystemunitdir"/sysinit.target.wants/systemd-udevd.service \
        "$systemdsystemunitdir"/sysinit.target.wants/systemd-udev-trigger.service

    # Install the hosts local user configurations if enabled.
    if [[ $hostonly ]]; then
        inst_multiple -H -o \
            "$systemdsystemconfdir"/systemd-udevd.service \
            "$systemdsystemconfdir/systemd-udevd.service.d/*.conf" \
            "$systemdsystemconfdir"/systemd-udev-trigger.service \
            "$systemdsystemconfdir/systemd-udev-trigger.service.d/*.conf" \
            "$systemdsystemconfdir"/systemd-udev-settle.service \
            "$systemdsystemconfdir/systemd-udev-settle.service.d/*.conf" \
            "$systemdsystemconfdir"/systemd-udevd-control.socket \
            "$systemdsystemconfdir/systemd-udevd-control.socket.d/*.conf" \
            "$systemdsystemconfdir"/systemd-udevd-kernel.socket \
            "$systemdsystemconfdir/systemd-udevd-kernel.socket.d/*.conf" \
            "$systemdsystemconfdir"/sockets.target.wants/systemd-udevd-control.socket \
            "$systemdsystemconfdir"/sockets.target.wants/systemd-udevd-kernel.socket \
            "$systemdsystemconfdir"/sysinit.target.wants/systemd-udevd.service \
            "$systemdsystemconfdir"/sysinit.target.wants/systemd-udev-trigger.service

        if dracut_module_included "hwdb"; then
            inst_multiple -H -o \
                "$systemdutilconfdir"/hwdb/hwdb.bin
        fi
    fi

    # Install required libraries.
    _arch=${DRACUT_ARCH:-$(uname -m)}
    inst_libdir_file {"tls/$_arch/",tls/,"$_arch/",}"libudev.so.*"

}

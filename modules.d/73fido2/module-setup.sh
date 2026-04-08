#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Prerequisite check(s) for module.
check() {
    # Return 255 to only include the module, if another module requires it.
    return 255
}

# Module dependency requirements.
depends() {
    # This module has external dependency on other module(s).
    echo systemd-udevd
    # Return 0 to include the dependent module(s) in the initramfs.
    return 0
}

# Install the required file(s) and directories for the module in the initramfs.
install() {
    # Install required libraries.
    inst_libdir_file \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"libfido2.so.*" \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"libz.so.*" \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"libcryptsetup.so.*" \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"cryptsetup/libcryptsetup-token-systemd-fido2.so" \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"libcbor.so.*" \
        {"tls/$DRACUT_ARCH/",tls/,"$DRACUT_ARCH/",}"libhidapi-hidraw.so.*"
}

#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Prerequisite check(s) for module.
check() {
    # If the binary(s) requirements are not fulfilled the module can't be installed
    require_binaries "$systemdutildir"/systemd-battery-check || return 1

    return 0
}

# Module dependency requirements.
depends() {
    # This module has external dependency on other module(s).
    echo systemd
    # Return 0 to include the dependent module(s) in the initramfs.
    return 0
}

# Install the required file(s) for the module in the initramfs.
install() {
    inst_multiple \
        "$systemdsystemunitdir"/systemd-battery-check.service \
        "$systemdsystemunitdir"/initrd.target.wants/systemd-battery-check.service \
        "$systemdutildir"/systemd-battery-check
}

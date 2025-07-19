#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# This module should be orders afer all modules that depends on it
# This is to make sure that all inst_sysusers calls are in place before systemd-sysusers is called.

# Prerequisite check(s) for module.
check() {
    # If the binary(s) requirements are not fulfilled the module can't be installed.
    require_binaries systemd-sysusers || return 1

    # Return 255 to only include the module, if another module requires it.
    return 255
}

# Install the required file(s) and directories for the module in the initramfs.
install() {
    inst_sysusers basic.conf

    # redirect stdout temporarily to FD 3 to use filter stderr
    {
        set -o pipefail
        systemd-sysusers --root="$initdir" 2>&1 >&3 | grep -v "^Creating " >&2
    } 3>&1

    # systemd-sysusers does not set any permission
    # set read and write permission for the current user
    [[ -f "$initdir/etc/gshadow" ]] && chmod u+rw "$initdir/etc/gshadow"
    [[ -f "$initdir/etc/shadow" ]] && chmod u+rw "$initdir/etc/shadow"
}

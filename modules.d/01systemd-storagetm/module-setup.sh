#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

check() {
    require_binaries \
        "$systemdutildir"/systemd-storagetm \
        || return 1

    # Return 255 to signal this is an optional module.
    return 255
}

depends() {
    echo systemd-networkd
    return 0
}

installkernel() {
    hostonly="" instmods nvmet_tcp thunderbolt_net
}

install() {
    inst_multiple -o \
        "$systemdutildir"/systemd-storagetm \
        "$systemdsystemunitdir"/storage-target-mode.target \
        "$systemdsystemunitdir"/systemd-storagetm.service
}

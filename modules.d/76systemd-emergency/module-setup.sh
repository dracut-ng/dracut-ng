#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

check() {
    require_binaries "$systemdutildir"/systemd-sulogin-shell || return 1

    return 255
}

depends() {
    echo systemd
}

install() {
    inst_multiple -o \
        "$systemdsystemunitdir"/emergency.target \
        "$systemdsystemunitdir"/emergency.service \
        "$systemdsystemunitdir"/rescue.target \
        "$systemdsystemunitdir"/rescue.service \
        "$systemdutildir"/systemd-sulogin-shell
}

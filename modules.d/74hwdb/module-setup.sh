#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

check() {
    if [[ $hostonly_mode == "strict" ]]; then
        return 255
    fi

    return 0
}

# called by dracut
install() {
    inst_multiple -o \
        "${udevdir}"/hwdb.bin

    # Install the hosts local user configurations if enabled.
    if [[ ${hostonly-} ]]; then
        inst_multiple -H -o \
            "$udevconfdir"/hwdb.bin
    fi
}

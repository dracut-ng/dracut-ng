#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

check() {
    # Return 255 to only include the module, if another module requires it.
    return 255
}

# called by dracut
install() {
    inst_script "$moddir/initqueue.sh" "/sbin/initqueue"

    if dracut_module_included "systemd"; then
        inst_script "$moddir/dracut-initqueue.sh" /usr/bin/dracut-initqueue
        inst_simple "$moddir/dracut-initqueue.service" "$systemdsystemunitdir/dracut-initqueue.service"
        inst_simple "$systemdsystemunitdir"/initrd.target.wants/dracut-initqueue.service

        # Enable systemd type unit(s)
        $SYSTEMCTL -q --root "$initdir" enable dracut-initqueue.service
    fi

    dracut_need_initqueue
}

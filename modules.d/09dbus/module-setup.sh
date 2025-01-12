#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Prerequisite check(s) for module.
check() {
    # We only want to return 255 since this is a meta module.
    return 255
}

# Module dependency requirements.
depends() {
    for module in dbus-broker dbus-daemon; do
        if dracut_module_included "$module"; then
            echo "$module"
            return 0
        fi
    done

    for module in dbus-broker dbus-daemon; do
        # install the first viable module, unless there omitted
        module_check $module > /dev/null 2>&1
        if [[ $? == 255 ]] && ! [[ " $omit_dracutmodules " == *\ $module\ * ]] && check_module "$module"; then
            echo "$module"
            return 0
        fi
    done

    echo "dbus-daemon"
    return 0
}

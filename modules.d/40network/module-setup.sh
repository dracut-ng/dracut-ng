#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    for module in network-manager systemd-networkd connman network-legacy; do
        if dracut_module_included "$module"; then
            echo "$module"
            return 0
        fi
    done

    for module in network-manager systemd-networkd connman; do
        # install the first viable module, unless there omitted
        module_check $module > /dev/null 2>&1
        if [[ $? == 255 ]] && ! [[ " $omit_dracutmodules " == *\ $module\ * ]] && check_module "$module"; then
            echo "$module"
            return 0
        fi
    done

    echo "network-legacy"
    return 0
}

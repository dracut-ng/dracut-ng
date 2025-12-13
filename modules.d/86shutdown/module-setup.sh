#!/bin/bash

# called by dracut
depends() {
    echo base
    return 0
}

# called by dracut
install() {
    local _d
    local _h
    inst_multiple umount poweroff reboot halt losetup stat sleep timeout
    inst_multiple -o kexec
    inst "$moddir/shutdown.sh" "$prefix/shutdown"

    for _h in "/var/lib/dracut/hooks" "/etc/dracut/hooks" "/lib/dracut/hooks"; do
        for _d in $hookdirs shutdown shutdown-emergency; do
            mkdir -m 0755 -p "${initdir}$_h/$_d"
        done
    done
}

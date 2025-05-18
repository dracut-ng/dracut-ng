#!/bin/bash

# called by dracut
depends() {
    echo base
    return 0
}

# called by dracut
install() {
    local _d
    inst_multiple umount poweroff reboot halt losetup stat sleep timeout
    inst_multiple -o kexec
    inst "$moddir/shutdown.sh" "$prefix/shutdown"
    mkdir -m 0755 -p "${initdir}"/var/lib/dracut/hooks

    # symlink to old hooks location for compatibility
    ln_r /var/lib/dracut/hooks /lib/dracut/hooks

    for _d in $hookdirs shutdown shutdown-emergency; do
        mkdir -m 0755 -p "${initdir}"/lib/dracut/hooks/"$_d"
    done
}

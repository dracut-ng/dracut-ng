#!/bin/bash

check() {
    # Only include the module if another module requires it
    return 255
}

depends() {
    if [[ $V == "2" ]]; then
        echo debug
    fi

    return 0
}

install() {
    # do not compress, do not strip
    export compress="cat"
    export do_strip="no"
    export do_hardlink="no"
    export early_microcode="no"
    export hostonly_cmdline="no"

    inst_simple /etc/os-release

    inst_multiple mkdir ln dd stty mount poweroff umount setsid sync cat grep

    for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
        [ -f "${_terminfodir}/l/linux" ] && break
    done
    inst_multiple -o "${_terminfodir}/l/linux"

    inst_binary "${dracutbasedir}/dracut-util" "/usr/bin/dracut-util"
    ln -s dracut-util "${initdir}/usr/bin/dracut-getarg"
    ln -s dracut-util "${initdir}/usr/bin/dracut-getargs"

    inst_script "${dracutbasedir}/modules.d/99base/dracut-lib.sh" "/lib/dracut-lib.sh"
    inst_script "${dracutbasedir}/modules.d/99base/dracut-dev-lib.sh" "/lib/dracut-dev-lib.sh"

    inst_script "$moddir/test-init.sh" "/sbin/init"

    inst_multiple -o plymouth
}

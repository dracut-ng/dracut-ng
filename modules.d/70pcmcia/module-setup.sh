#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    echo udev-rules
    return 0
}

# called by dracut
installkernel() {
    hostonly=$(optional_hostonly) instmods pcmcia \
        "=drivers/pcmcia"
}

# called by dracut
install() {
    inst_rules 60-pcmcia.rules

    inst_multiple -o \
        "${udevdir}"/pcmcia-socket-startup \
        "${udevdir}"/pcmcia-check-broken-cis

    # Install the hosts local user configurations if enabled.
    if [[ ${hostonly-} ]]; then
        inst_multiple -H -o \
            /etc/pcmcia/config.opts
    fi
}

#!/usr/bin/bash

# called by dracut
check() {
    # only enable on systems that use crypto-policies
    [ -d "$dracutsysrootdir/etc/crypto-policies" ] && return 0

    # include when something else depends on it or it is explicitly requested
    return 255
}

# called by dracut
depends() {
    echo fips
    return 0
}

# called by dracut
install() {
    inst_hook pre-pivot 01 "$moddir/fips-crypto-policies.sh"

    inst_multiple mount
}

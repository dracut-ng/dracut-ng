#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if ! fipsmode=$(getarg fips) || [ "$fipsmode" = "0" ]; then
    :
elif [ -z "$fipsmode" ]; then
    die "FIPS mode have to be enabled by 'fips=1' not just 'fips'"
elif getarg boot= > /dev/null; then
    . /sbin/fips.sh
    fips_info "fips-boot: start"
    if mount_boot; then
        do_fips || die "FIPS integrity test failed"
    fi
    fips_info "fips-boot: done!"
fi

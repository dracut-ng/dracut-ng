#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if ! fipsmode=$(getarg fips) || [ "$fipsmode" = "0" ]; then
    :
elif [ -z "$fipsmode" ]; then
    die "FIPS mode have to be enabled by 'fips=1' not just 'fips'"
elif ! [ -f /tmp/fipsdone ]; then
    . /sbin/fips.sh
    fips_info "fips-noboot: start"
    mount_boot
    do_fips || die "FIPS integrity test failed"
    fips_info "fips-noboot: done!"
fi

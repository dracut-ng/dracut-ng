#!/bin/sh

command -v ismounted > /dev/null || . /lib/dracut-lib.sh

if [ "${fstype}" = "virtiofs" ] || [ "${root%%:*}" = "virtiofs" ]; then
    if ! load_fstype virtiofs; then
        die "virtiofs is required but not available."
    fi

    mount -t virtiofs -o "$rflags" "${root#virtiofs:}" "$NEWROOT" 2>&1 | vinfo
    if ! ismounted "$NEWROOT"; then
        die "virtiofs: failed to mount root fs"
    fi

    info "virtiofs: root fs mounted (options: '${rflags}')"
fi
:

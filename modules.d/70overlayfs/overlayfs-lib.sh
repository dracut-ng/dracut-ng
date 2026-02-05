#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

# Fetch non-boolean value for rd.overlay or fall back to rd.live.overlay
get_rd_overlay() {
    local overlay

    overlay=$(getarg rd.overlay)
    case $overlay in
        0 | no | off | "" | 1)
            overlay=$(getarg rd.live.overlay) || return 1
            warn "Kernel command line option 'rd.live.overlay' is deprecated, use 'rd.overlay' instead."
            ;;
    esac
    echo "$overlay"
}

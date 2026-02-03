#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

set_new_option() {
    local old="$1"
    local new="$2"
    local value="$3"

    warn "Kernel command line option '$old' is deprecated, use '$new' instead."
    echo "${new}${value:+=$value}" >> /run/initramfs/cmdline.d/70-overlayfs.conf
}

map_option() {
    local old="$1"
    local new="$2"

    if getarg "$new" > /dev/null; then
        return 0
    fi

    value=$(getarg "$old") || return 0
    set_new_option "$old" "$new" "$value"
}

map_option rd.live.overlay rd.overlay
map_option rd.live.overlay.overlayfs rd.overlayfs
map_option rd.live.overlay.readonly rd.overlay.readonly
map_option rd.live.overlay.reset rd.overlay.reset

#!/bin/bash

pkglib_dir() {
    local _dirs="/usr/lib/plymouth /usr/libexec/plymouth/"
    local _arch=${DRACUT_ARCH:-$(uname -m)}
    [ -n "$_arch" ] && _dirs+=" /usr/lib/$_arch/plymouth"
    for _dir in $_dirs; do
        if [ -x "${dracutsysrootdir-}$_dir"/plymouth-populate-initrd ]; then
            echo "$_dir"
            return
        fi
    done
}

read_setting_from_config() {
    local setting="$1"
    local config_file="$2"
    sed -n "s/^${setting}= *\([^ ]\+\) */\1/p" "$config_file"
}

use_simpledrm() {
    local config use_simpledrm config_dirs=()
    if [[ $hostonly ]]; then
        config_dirs+=("${dracutsysrootdir-}/etc/plymouth/plymouthd.conf")
    fi
    for config in "${config_dirs[@]}" "${dracutsysrootdir-}/usr/share/plymouth/plymouthd.defaults"; do
        use_simpledrm=$(read_setting_from_config UseSimpledrm "$config")
        if [[ $use_simpledrm -ge 1 ]]; then
            return 0
        fi
        if [[ $use_simpledrm == "0" ]]; then
            return 1
        fi
    done
    return 1
}

# called by dracut
check() {
    [[ "$mount_needs" ]] && return 1
    [[ $(pkglib_dir) ]] || return 1

    require_binaries plymouthd plymouth plymouth-set-default-theme || return 1

    return 0
}

# called by dracut
depends() {
    if use_simpledrm; then
        echo simpledrm
    else
        echo drm
    fi
}

# called by dracut
install() {
    PKGLIBDIR=$(pkglib_dir)
    if grep -q nash "${dracutsysrootdir-}${PKGLIBDIR}"/plymouth-populate-initrd \
        || [ ! -x "${dracutsysrootdir-}${PKGLIBDIR}"/plymouth-populate-initrd ]; then
        # shellcheck disable=SC1090
        . "$moddir"/plymouth-populate-initrd.sh
    else
        PLYMOUTH_POPULATE_SOURCE_FUNCTIONS="$dracutfunctions" \
            "${dracutsysrootdir-}${PKGLIBDIR}"/plymouth-populate-initrd -t "$initdir" 2> /dev/null
    fi

    inst_hook emergency 50 "$moddir"/plymouth-emergency.sh

    inst_multiple readlink

    inst_multiple plymouthd plymouth plymouth-set-default-theme

    if ! dracut_module_included "systemd"; then
        inst_hook pre-trigger 10 "$moddir"/plymouth-pretrigger.sh
        inst_hook pre-pivot 90 "$moddir"/plymouth-newroot.sh
    fi
}

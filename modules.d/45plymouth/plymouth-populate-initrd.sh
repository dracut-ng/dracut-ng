#!/bin/bash

read_setting_from_config() {
    local setting="$1"
    local config_file="$2"
    sed -n "s/^${setting}= *\([^ ]\+\) */\1/p" "$config_file"
}

get_plymouth_theme() {
    local config theme
    for config in "${dracutsysrootdir-}/etc/plymouth/plymouthd.conf" "${dracutsysrootdir-}/usr/share/plymouth/plymouthd.defaults"; do
        theme=$(read_setting_from_config Theme "$config")
        if [[ -n $theme ]]; then
            echo "$theme"
            return
        fi
    done
    echo spinner
}

PLYMOUTH_LOGO_FILE="/usr/share/pixmaps/system-logo-white.png"
PLYMOUTH_THEME=$(get_plymouth_theme)

inst_multiple plymouthd plymouth

test -e "${PLYMOUTH_LOGO_FILE}" && inst_simple "${PLYMOUTH_LOGO_FILE}"

# shellcheck disable=SC2174
mkdir -m 0755 -p "${initdir}/usr/share/plymouth"

inst_libdir_file "plymouth/text.so" "plymouth/details.so"

if [[ $hostonly ]]; then
    inst_multiple \
        "/usr/share/plymouth/themes/details/details.plymouth" \
        "/usr/share/plymouth/themes/text/text.plymouth"

    if [[ -d ${dracutsysrootdir-}/usr/share/plymouth/themes/${PLYMOUTH_THEME} ]]; then
        for x in "/usr/share/plymouth/themes/${PLYMOUTH_THEME}"/*; do
            [[ -f "${dracutsysrootdir-}$x" ]] || break
            inst "$x"
        done
    fi

    if [[ -L ${dracutsysrootdir-}/usr/share/plymouth/themes/default.plymouth ]]; then
        inst /usr/share/plymouth/themes/default.plymouth
        # Install plugin for this theme
        PLYMOUTH_PLUGIN=$(grep "^ModuleName=" "${dracutsysrootdir-}"/usr/share/plymouth/themes/default.plymouth | while read -r _ b _ || [ -n "$b" ]; do echo "$b"; done)
        inst_libdir_file "plymouth/${PLYMOUTH_PLUGIN}.so"
    fi
else
    for x in "${dracutsysrootdir-}"/usr/share/plymouth/themes/{text,details}/*; do
        [[ -f $x ]] || continue
        THEME_DIR=$(dirname "${x#"${dracutsysrootdir-}"}")
        # shellcheck disable=SC2174
        mkdir -m 0755 -p "${initdir}/$THEME_DIR"
        inst_multiple "${x#"${dracutsysrootdir-}"}"
    done
    (
        cd "${initdir}"/usr/share/plymouth/themes || exit
        ln -s text/text.plymouth default.plymouth 2>&1
    )
fi

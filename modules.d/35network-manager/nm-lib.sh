#!/bin/sh

command -v getcmdline > /dev/null || . /lib/dracut-lib.sh

nm_generate_connections() {
    if [ -e /usr/lib/systemd/system/NetworkManager-config-initrd.service ]; then
        systemctl restart NetworkManager-config-initrd.service
    else
        rm -f /run/NetworkManager/system-connections/*
        if [ -x /usr/libexec/nm-initrd-generator ]; then
            # shellcheck disable=SC2046
            /usr/libexec/nm-initrd-generator -- $(getcmdline)
        elif [ -x /usr/lib/nm-initrd-generator ]; then
            # shellcheck disable=SC2046
            /usr/lib/nm-initrd-generator -- $(getcmdline)
        else
            warn "nm-initrd-generator not found"
        fi

        if getargbool 0 rd.neednet; then
            for i in /usr/lib/NetworkManager/system-connections/* \
                /run/NetworkManager/system-connections/* \
                /etc/NetworkManager/system-connections/*; do
                [ -f "$i" ] || continue
                echo '[ -f /tmp/nm.done ]' > "$hookdir"/initqueue/finished/nm.sh
                mkdir -p /run/NetworkManager/initrd
                : > /run/NetworkManager/initrd/neednet # activate NM services
                break
            done
        fi
    fi
}

nm_reload_connections() {
    [ -n "$DRACUT_SYSTEMD" ] \
        && systemctl -q is-active nm-initrd.service NetworkManager-initrd.service \
        && nmcli connection reload
}

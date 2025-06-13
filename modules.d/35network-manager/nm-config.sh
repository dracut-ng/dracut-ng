#!/bin/sh

command -v getargbool > /dev/null || . /lib/dracut-lib.sh

[ -e /usr/lib/systemd/system/NetworkManager-initrd.service ] \
    && nm_service_name="NetworkManager-initrd" \
    || nm_service_name="nm-initrd"

if [ -n "$netroot" ] || [ -e /tmp/net.ifaces ]; then
    echo rd.neednet >> /etc/cmdline.d/35-neednet.conf
fi

if getargbool 0 rd.debug; then
    # shellcheck disable=SC2174
    mkdir -m 0755 -p /run/NetworkManager/conf.d
    (
        echo '[.config]'
        echo 'enable=env:initrd'
        echo
        echo '[logging]'
        echo 'level=TRACE'
    ) > /run/NetworkManager/conf.d/initrd-logging.conf

    if [ -n "$DRACUT_SYSTEMD" ]; then
        # Enable tty output if a usable console is found
        # See https://github.com/coreos/fedora-coreos-tracker/issues/943
        # shellcheck disable=SC2217
        if [ -w /dev/console ] && (echo < /dev/console) > /dev/null 2> /dev/null; then
            mkdir -p /run/systemd/system/"$nm_service_name".service.d
            cat << EOF > /run/systemd/system/"$nm_service_name".service.d/tty-output.conf
[Service]
StandardOutput=tty
EOF
            systemctl --no-block daemon-reload
        fi
    fi
fi

if [ "$nm_service_name" = "nm-initrd" ]; then
    command -v nm_generate_connections > /dev/null || . /lib/nm-lib.sh
    nm_generate_connections
fi

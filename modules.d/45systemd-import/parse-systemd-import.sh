#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

if getarg rd.systemd.pull= > /dev/null; then
    echo "rd.neednet=1" > /etc/cmdline.d/01-systemd-import.conf
    if ! getarg "ip="; then
        echo "ip=dhcp" >> /etc/cmdline.d/01-systemd-import.conf
    fi
fi

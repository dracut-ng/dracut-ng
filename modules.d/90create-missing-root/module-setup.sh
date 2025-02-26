#!/bin/bash

check() {
    # Return 255 to only include the module, if another module requires it.
    return 255
}

depends() {
    echo systemd-repart systemd-cryptsetup overlayfs
}

_load_conf_file() {
    if [ -f "/etc/create-missing-root.conf" ]; then
        CONF_LOCAL_FILE="/etc/create-missing-root.conf"
    else
        CONF_LOCAL_FILE="${moddir}/default-root.conf"
    fi
    # shellcheck disable=SC1090
    . "$CONF_LOCAL_FILE"
}

installkernel() {
    hostonly='' instmods -c btrfs ext4 xfs
}

install() {
    inst_simple "$moddir/build-root.service" "$systemdsystemunitdir/build-root.service"
    inst_simple "$moddir/build-root.sh" "/usr/bin/build-root.sh"
    $SYSTEMCTL -q --root "$initdir" enable build-root.service

    inst_simple "$moddir/prepare-root.service" "$systemdsystemunitdir/prepare-root.service"
    inst_simple "$moddir/prepare-root.sh" "/usr/bin/prepare-root.sh"
    $SYSTEMCTL -q --root "$initdir" enable prepare-root.service

    inst_simple "$moddir/finish-root.service" "$systemdsystemunitdir/finish-root.service"
    inst_simple "$moddir/finish-root.sh" "/usr/bin/finish-root.sh"
    $SYSTEMCTL -q --root "$initdir" enable finish-root.service

    _load_conf_file
    inst_simple "$CONF_LOCAL_FILE" "/etc/create-missing-root.conf"

    inst_multiple -o mkfs.btrfs mkfs.ext4 mkfs.xfs lsblk jq chroot
}

#!/bin/bash

check() {
    # Return 255 to only include the module, if another module requires it.
    return 255
}

depends() {
    echo systemd-repart systemd-cryptsetup overlayfs
}

# sets CONF_LOCAL_FILE to the right config file, and
# sources it
_load_conf_file() {
    if [ -f "/etc/create-missing-root.conf" ]; then
        CONF_LOCAL_FILE="/etc/create-missing-root.conf"
    else
        CONF_LOCAL_FILE="${moddir}/default-root.conf"
    fi
    # shellcheck disable=SC1090
    . "$CONF_LOCAL_FILE"
}

# sets FS_TO_LOAD to contain the chosen fs
_get_root_fs() {
    local fs="$1"
    VALID_FS=("ext4" "xfs" "btrfs")
    FS_TO_LOAD="ext4"
    if [[ ${VALID_FS[*]} =~ ${fs} ]]; then
        FS_TO_LOAD="$fs"
    else
        if [ -n "$fs" ]; then
            dwarn "Allowed filesystems are" "${VALID_FS[@]}"
        fi
        dwarn "Using default fs ext4"
    fi
}

installkernel() {
    _load_conf_file
    _get_root_fs "$NEW_ROOT_FS"
    hostonly='' instmods -c "$FS_TO_LOAD"
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

    _get_root_fs "$NEW_ROOT_FS"
    inst_multiple -o mkfs."$FS_TO_LOAD" lsblk jq chroot
}

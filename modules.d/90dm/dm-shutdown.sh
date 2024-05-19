#!/bin/sh

_remove_dm() {
    local dev="$1"
    local final="$2"
    local s
    local devname

    for s in /sys/block/"${dev}"/holders/dm-*; do
        [ -e "${s}" ] || continue
        _remove_dm "${s##*/}" "$final" || return $?
    done

    read -r devname < /sys/block/"${dev}"/dm/name
    case $(cat /sys/block/"${dev}"/dm/uuid) in
        mpath-*)
            # multipath devices might have MD devices on top,
            # which are removed after this script. So do not
            # remove those to avoid spurious errors
            return 0
            ;;
        CRYPT-*)
            if command -v systemd-cryptsetup > /dev/null; then
                DM_DISABLE_UDEV=true SYSTEMD_LOG_LEVEL=debug systemd-cryptsetup detach "$devname" && return 0
            elif command -v cryptsetup > /dev/null; then
                DM_DISABLE_UDEV=true cryptsetup close --debug "$devname" && return 0
            else
                dmsetup -v --noudevsync remove "$devname"
                return $?
            fi

            # try using plain dmsetup if we're on the final attempt.
            [ -z "$final" ] && return 1
            ;;
    esac

    dmsetup -v --noudevsync remove "$devname"
    return $?
}

_do_dm_shutdown() {
    local ret=0
    local final="$1"
    local dev

    info "Disassembling device-mapper devices"
    for dev in /sys/block/dm-*; do
        [ -e "${dev}" ] || continue
        if [ "x$final" != "x" ]; then
            _remove_dm "${dev##*/}" "$final" || ret=$?
        else
            _remove_dm "${dev##*/}" "$final" > /dev/null 2>&1 || ret=$?
        fi
    done
    if [ "x$final" != "x" ]; then
        info "dmsetup ls --tree"
        dmsetup ls --tree 2>&1 | vinfo
    fi
    return $ret
}

if command -v dmsetup > /dev/null \
    && [ "x$(dmsetup status)" != "xNo devices found" ]; then
    _do_dm_shutdown "$1"
else
    :
fi

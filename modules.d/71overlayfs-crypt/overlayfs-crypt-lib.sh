#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

parse_overlay_opts() {
    local input="$1" ns="${2:-_RET_}"
    local oifs="$IFS" tok key val

    _RET=""
    set -f
    IFS=","
    # shellcheck disable=SC2086
    set -- $input
    IFS="$oifs"
    set +f

    for tok in "$@"; do
        key="${tok%%=*}"
        val="${tok#*=}"
        [ "$key" = "$tok" ] && val=""
        case "$key" in
            dev | pass | mapname | fstype | mkfs | timeout)
                eval "${ns}${key}='${val}'"
                _RET="${_RET:+$_RET }${ns}${key}"
                ;;
            *)
                warn "overlayfs-crypt: unknown option '$key'"
                ;;
        esac
    done
    return 0
}

generate_random_password() {
    local tmpf entropy_sources pass
    local persist_dir="/run/initramfs"

    [ -d "$persist_dir" ] || mkdir -p "$persist_dir"

    tmpf=$(mktemp "${persist_dir}/overlayfs-crypt.XXXXXX") || {
        warn "overlayfs-crypt: failed to create temp file for password"
        return 1
    }

    entropy_sources="/proc/sys/kernel/random/boot_id /proc/sys/kernel/random/uuid /dev/urandom"

    stat -L /dev/* /proc/* /sys/* > "$tmpf" 2>&1 || true

    for src in $entropy_sources; do
        [ -e "$src" ] && head -c 4096 "$src" >> "$tmpf" 2> /dev/null
    done

    pass=$(sha512sum "$tmpf" 2> /dev/null) || {
        rm -f "$tmpf"
        warn "overlayfs-crypt: failed to generate password"
        return 1
    }
    pass="${pass%% *}"

    printf "%s" "$pass" > "${persist_dir}/overlayfs.passwd"
    chmod 400 "${persist_dir}/overlayfs.passwd"

    rm -f "$tmpf"
    _RET="$pass"
    return 0
}

_overlayfs_crypt_fallback_tmpfs() {
    [ -d /run/overlayfs ] || {
        mkdir -m 0755 -p /run/initramfs/overlay/overlayfs
        mkdir -m 0755 -p /run/initramfs/overlay/ovlwork
        ln -sf /run/initramfs/overlay/overlayfs /run/overlayfs
        ln -sf /run/initramfs/overlay/ovlwork /run/ovlwork
    }
    # Signal mount-overlayfs.sh to proceed with the overlay mount
    : > /run/overlayfs-crypt-ready
}

overlayfs_crypt_setup() {
    local options="$1"
    local dev="" pass="" mapname="overlay-crypt" fstype="ext4" mkfs="1" timeout="0"
    local crypt_dev

    parse_overlay_opts "$options" "_ovl_" || return 1

    dev="${_ovl_dev:-}"
    pass="${_ovl_pass:-}"
    mapname="${_ovl_mapname:-$mapname}"
    fstype="${_ovl_fstype:-$fstype}"
    mkfs="${_ovl_mkfs:-$mkfs}"
    timeout="${_ovl_timeout:-$timeout}"

    [ -n "$dev" ] || {
        warn "overlayfs-crypt: dev= parameter is required"
        return 1
    }

    case "$dev" in
        LABEL=* | UUID=* | PARTLABEL=* | PARTUUID=*)
            dev=$(label_uuid_to_dev "$dev")
            ;;
        /dev/*) ;;
        *)
            dev="/dev/$dev"
            ;;
    esac

    if [ "$timeout" -gt 0 ] 2> /dev/null; then
        wait_for_dev -n "$dev" "$timeout" || {
            warn "overlayfs-crypt: device $dev not available after ${timeout}s"
            return 1
        }
    fi

    # Resolve symlink to actual block device
    local real_dev="$dev"
    if [ -L "$dev" ]; then
        real_dev=$(readlink -f "$dev" 2> /dev/null) || real_dev="$dev"
    fi

    [ -b "$real_dev" ] || {
        warn "overlayfs-crypt: device $real_dev not found"
        return 1
    }

    dev="$real_dev"

    info "overlayfs-crypt: setting up encrypted overlay on $dev"

    modprobe -q dm_mod 2> /dev/null || true
    modprobe -q dm_crypt 2> /dev/null || true

    crypt_dev="/dev/mapper/$mapname"

    if [ -n "$pass" ]; then
        if printf "%s" "$pass" | cryptsetup luksOpen "$dev" "$mapname" --key-file - 2> /dev/null; then
            info "overlayfs-crypt: opened existing LUKS device at $dev"
            wait_for_dev -n "$crypt_dev" 20 || {
                warn "overlayfs-crypt: $crypt_dev did not appear"
                return 1
            }
            _RET_DEVICE="$crypt_dev"
            return 0
        fi

        if [ "$mkfs" = "0" ]; then
            warn "overlayfs-crypt: failed to open LUKS device at $dev (mkfs=0)"
            return 1
        fi

        info "overlayfs-crypt: creating new LUKS device at $dev"
    else
        if [ "$mkfs" = "0" ]; then
            warn "overlayfs-crypt: mkfs=0 but no password provided"
            return 1
        fi

        generate_random_password || return 1
        pass="$_RET"
        info "overlayfs-crypt: generated random password, stored in /run/initramfs/overlayfs.passwd"
    fi

    info "overlayfs-crypt: wiping $dev"
    wipefs -a "$dev" || {
        warn "overlayfs-crypt: failed to wipe $dev"
        return 1
    }

    info "overlayfs-crypt: formatting $dev with LUKS"
    # DM_DISABLE_UDEV=1 prevents cryptsetup from waiting for udev to process the device
    if ! printf "%s" "$pass" | DM_DISABLE_UDEV=1 cryptsetup luksFormat --pbkdf pbkdf2 -q "$dev" --key-file -; then
        warn "overlayfs-crypt: luksFormat failed on $dev"
        return 1
    fi

    info "overlayfs-crypt: opening LUKS device"
    if ! printf "%s" "$pass" | DM_DISABLE_UDEV=1 cryptsetup luksOpen "$dev" "$mapname" --key-file -; then
        warn "overlayfs-crypt: luksOpen failed on $dev"
        return 1
    fi
    udevadm settle 2> /dev/null || true

    info "overlayfs-crypt: LUKS device opened, waiting for $crypt_dev"

    wait_for_dev -n "$crypt_dev" 20 || {
        warn "overlayfs-crypt: $crypt_dev did not appear after luksOpen"
        return 1
    }

    info "overlayfs-crypt: creating $fstype filesystem on $crypt_dev"
    case "$fstype" in
        ext2 | ext3 | ext4)
            mkfs."$fstype" -q "$crypt_dev" || {
                warn "overlayfs-crypt: mkfs.$fstype failed on $crypt_dev"
                cryptsetup luksClose "$mapname"
                return 1
            }
            ;;
        *)
            warn "overlayfs-crypt: unsupported filesystem type '$fstype'"
            cryptsetup luksClose "$mapname"
            return 1
            ;;
    esac

    info "overlayfs-crypt: successfully set up encrypted overlay at $crypt_dev"
    _RET_DEVICE="$crypt_dev"
    return 0
}

#!/bin/bash

# called by dracut
check() {
    local fs
    # if cryptsetup is not installed, then we cannot support encrypted devices.
    require_any_binary "$systemdutildir"/systemd-cryptsetup cryptsetup || return 1

    [[ $hostonly_mode == "strict" ]] || [[ $mount_needs ]] && {
        for fs in "${host_fs_types[@]}"; do
            [[ $fs == "crypto_LUKS" ]] && return 0
        done
        return 255
    }

    return 0
}

# called by dracut
depends() {
    echo dm rootfs-block initqueue
}

# called by dracut
installkernel() {
    local _arch=${DRACUT_ARCH:-$(uname -m)}
    local _s390drivers=
    if [[ $_arch == "s390" ]] || [[ $_arch == "s390x" ]]; then
        _s390drivers="=drivers/s390/crypto"
    fi

    hostonly="" instmods drbg dm_crypt ${_s390drivers:+"$_s390drivers"}

    # in case some of the crypto modules moved from compiled in
    # to module based, try to install those modules
    # best guess
    if [[ $hostonly_mode == "strict" ]] || [[ $mount_needs ]]; then
        # dmsetup returns s.th. like
        # cryptvol: 0 2064384 crypt aes-xts-plain64 :64:logon:cryptsetup:....
        dmsetup table | while read -r name _ _ is_crypt cipher _; do
            [[ $is_crypt == "crypt" ]] || continue
            # get the device name
            name=/dev/$(dmsetup info -c --noheadings -o blkdevname "${name%:}")
            # check if the device exists as a key in our host_fs_types (even with null string)
            if [[ ${host_fs_types[$name]+_} ]]; then
                # split the cipher aes-xts-plain64 in pieces
                IFS='-:' read -ra mods <<< "$cipher"
                # try to load the cipher part with "crypto-" prepended
                # in non-hostonly mode
                hostonly='' instmods "${mods[@]/#/crypto-}" "crypto-$cipher"
            fi
        done
    else
        hostonly='' instmods "=crypto"
    fi
    return 0
}

# called by dracut
cmdline() {
    local dev UUID
    for dev in "${!host_fs_types[@]}"; do
        [[ ${host_fs_types[$dev]} != "crypto_LUKS" ]] && continue

        UUID=$(
            blkid -u crypto -o export "$dev" \
                | while read -r line || [ -n "$line" ]; do
                    [[ ${line#UUID} == "$line" ]] && continue
                    printf "%s" "${line#UUID=}"
                    break
                done
        )
        [[ ${UUID} ]] || continue
        printf "%s" " rd.luks.uuid=luks-${UUID}"
    done
}

# called by dracut
install() {

    if [[ $hostonly_cmdline == "yes" ]]; then
        local _cryptconf
        _cryptconf=$(cmdline)
        [[ $_cryptconf ]] && printf "%s\n" "$_cryptconf" >> "${initdir}/etc/cmdline.d/90crypt.conf"
    fi

    inst_hook cmdline 30 "$moddir/parse-crypt.sh"
    if ! dracut_module_included "systemd"; then
        inst_multiple cryptsetup rmdir readlink umount
        inst_script "$moddir"/cryptroot-ask.sh /sbin/cryptroot-ask
        inst_script "$moddir"/probe-keydev.sh /sbin/probe-keydev
        inst_hook cmdline 10 "$moddir/parse-keydev.sh"
        inst_hook cleanup 30 "$moddir/crypt-cleanup.sh"
    fi

    if [[ $hostonly ]] && [[ -f $dracutsysrootdir/etc/crypttab ]]; then
        # filter /etc/crypttab for the devices we need
        while read -r _mapper _dev _luksfile _luksoptions || [ -n "$_mapper" ]; do
            [[ $_mapper == \#* ]] && continue
            [[ $_dev ]] || continue

            [[ $_dev == PARTUUID=* ]] \
                && _dev="/dev/disk/by-partuuid/${_dev#PARTUUID=}"

            [[ $_dev == UUID=* ]] \
                && _dev="/dev/disk/by-uuid/${_dev#UUID=}"

            [[ $_dev == ID=* ]] \
                && _dev="/dev/disk/by-id/${_dev#ID=}"

            echo "$_dev $(blkid "$_dev" -s UUID -o value)" >> "${initdir}/etc/block_uuid.map"

            # loop through the options to check for the force option
            luksoptions=${_luksoptions}
            OLD_IFS="${IFS}"
            IFS=,
            # shellcheck disable=SC2086
            set -- ${luksoptions}
            IFS="${OLD_IFS}"

            forceentry=""
            while [ $# -gt 0 ]; do
                case $1 in
                    force | x-initrd.attach)
                        forceentry="yes"
                        break
                        ;;
                esac
                shift
            done

            # include the entry regardless
            if [ "${forceentry}" = "yes" ]; then
                echo "$_mapper $_dev $_luksfile $_luksoptions"
            else
                for _hdev in "${!host_fs_types[@]}"; do
                    [[ ${host_fs_types[$_hdev]} == "crypto_LUKS" ]] || continue
                    if [[ $_hdev -ef $_dev ]] || [[ /dev/block/$_hdev -ef $_dev ]]; then
                        echo "$_mapper $_dev $_luksfile $_luksoptions"
                        break
                    fi
                done
            fi
        done < "$dracutsysrootdir"/etc/crypttab > "$initdir"/etc/crypttab

        # Remove empty /etc/crypttab to allow creating it later
        if [ -s "$initdir"/etc/crypttab ]; then
            mark_hostonly /etc/crypttab
        else
            rm -f "$initdir"/etc/crypttab
        fi
    fi

    inst_multiple -o stty
    inst_simple "$moddir/crypt-lib.sh" "/lib/dracut-crypt-lib.sh"
    inst_script "$moddir/crypt-run-generator.sh" "/sbin/crypt-run-generator"

    # Install required libraries.
    _arch=${DRACUT_ARCH:-$(uname -m)}
    inst_libdir_file \
        {"tls/$_arch/",tls/,"$_arch/",}"/ossl-modules/fips.so" \
        {"tls/$_arch/",tls/,"$_arch/",}"/ossl-modules/legacy.so"
}

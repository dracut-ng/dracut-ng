#!/bin/bash

check() {
    require_kernel_modules loop overlay || return 1

    return 255
}

depends() {
    local _handler

    _handler=$(squash_get_handler) || return 1

    echo "systemd-initrd $_handler"
    return 0
}

squash_get_handler() {
    local _module _handler

    for _module in squash-squashfs squash-erofs; do
        if dracut_module_included "$_module"; then
            _handler="$_module"
            break
        fi
    done

    if [ -z "$_handler" ]; then
        if check_module "squash-squashfs"; then
            _handler="squash-squashfs"
        elif check_module "squash-erofs"; then
            _handler="squash-erofs"
        else
            dfatal "No valid handler for found"
            return 1
        fi
    fi

    echo "$_handler"
}

squash_install() {
    local _busybox _dir
    _busybox=$(find_binary busybox)

    # Create mount points for squash loader and basic directories
    mkdir -p "$initdir"/squash
    for _dir in squash usr/bin usr/sbin usr/lib; do
        mkdir -p "$squashdir/$_dir"
        [[ $_dir == usr/* ]] && ln_r "/$_dir" "${_dir#usr}"
    done

    # Install required modules and binaries for the squash image init script.
    if [[ $_busybox ]]; then
        module_install "busybox"
    else
        DRACUT_RESOLVE_DEPS=1 inst_multiple sh mount modprobe mkdir switch_root grep umount

        # libpthread workaround: pthread_cancel wants to dlopen libgcc_s.so
        inst_libdir_file -o "libgcc_s.so*"

        # FIPS workaround for Fedora/RHEL: libcrypto needs libssl when FIPS is enabled
        [[ $DRACUT_FIPS_MODE ]] && inst_libdir_file -o "libssl.so*"
    fi

    hostonly="" instmods "loop" "overlay"
    dracut_kernel_post

    # Install squash image init script.
    inst_simple "$moddir"/init-squash.sh /init

    # make sure that library links are correct and up to date for squash loader
    build_ld_cache
}

squash_installpost() {
    local _file

    DRACUT_SQUASH_POST_INST=1 module_install "$(squash_get_handler)"

    # Rescue the dracut spec files so dracut rebuild and lsinitrd can work
    for _file in "$initdir"/usr/lib/dracut/*; do
        [[ -f $_file ]] || continue
        DRACUT_RESOLVE_DEPS=1 dstdir=$squashdir inst "$_file" "${_file#"$initdir"}"
    done

    # Remove everything that got squashed into the image
    for _file in "$initdir"/*; do
        [[ $_file == "$squashdir" ]] && continue
        rm -rf "$_file"
    done
    mv "$squashdir"/* "$initdir"
}

install() {

    if [[ $DRACUT_SQUASH_POST_INST ]]; then
        squash_installpost
    else
        dstdir="$squashdir" squash_install
    fi
}

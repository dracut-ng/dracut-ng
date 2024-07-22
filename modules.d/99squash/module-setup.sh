#!/bin/bash

check() {
    require_binaries mksquashfs unsquashfs || return 1
    require_kernel_modules squashfs loop overlay || return 1

    return 255
}

depends() {
    echo "systemd-initrd"
    return 0
}

squash_install() {
    local _busybox
    _busybox=$(find_binary busybox)

    # Create mount points for squash loader
    mkdir -p "$initdir"/squash/
    mkdir -p "$squashdir"/squash/

    # Install required modules and binaries for the squash image init script.
    if [[ $_busybox ]]; then
        inst "$_busybox" /usr/bin/busybox
        for _i in sh echo mount modprobe mkdir switch_root grep umount; do
            ln_r /usr/bin/busybox /usr/bin/$_i
        done
    else
        DRACUT_RESOLVE_DEPS=1 inst_multiple sh mount modprobe mkdir switch_root grep umount

        # libpthread workaround: pthread_cancel wants to dlopen libgcc_s.so
        inst_libdir_file -o "libgcc_s.so*"

        # FIPS workaround for Fedora/RHEL: libcrypto needs libssl when FIPS is enabled
        [[ $DRACUT_FIPS_MODE ]] && inst_libdir_file -o "libssl.so*"
    fi

    hostonly="" instmods "loop" "squashfs" "overlay"
    dracut_kernel_post

    # Install squash image init script.
    ln_r /usr/bin /bin
    ln_r /usr/sbin /sbin
    inst_simple "$moddir"/init-squash.sh /init

    # make sure that library links are correct and up to date for squash loader
    build_ld_cache
}

squash_installpost() {
    local _img="$squashdir"/squash-root.img
    local _comp _file

    # shellcheck disable=SC2086
    if [[ $squash_compress ]]; then
        if ! mksquashfs /dev/null "$DRACUT_TMPDIR"/.squash-test.img -no-progress -comp $squash_compress &> /dev/null; then
            dwarn "mksquashfs doesn't support compressor '$squash_compress', failing back to default compressor."
        else
            _comp="$squash_compress"
        fi
    fi

    # shellcheck disable=SC2086
    if ! mksquashfs "$initdir" "$_img" \
        -no-xattrs -no-exports -noappend -no-recovery -always-use-fragments \
        -no-progress ${_comp:+-comp $_comp} \
        -e "$squashdir" 1> /dev/null; then
        dfatal "Failed making squash image"
        exit 1
    fi

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

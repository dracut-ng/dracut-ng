#!/bin/bash

check() {
    require_binaries mkfs.erofs fsck.erofs || return 1
    require_kernel_modules erofs || return 1

    return 255
}

depends() {
    echo "squash"
    return 0
}

erofs_install() {
    hostonly="" instmods "erofs"
}

erofs_installpost() {
    local _img="$squashdir/erofs-root.img"
    local -a _erofs_args

    _erofs_args+=("--exclude-path=$squashdir")
    _erofs_args+=("-E" "fragments")

    if [[ -n $squash_compress ]]; then
        if mkfs.erofs "${_erofs_args[@]}" -z "$squash_compress" "$_img" "$initdir" &> /dev/null; then
            return
        fi
        dwarn "mkfs.erofs doesn't support compressor '$squash_compress', failing back to default compressor."
    fi

    if ! mkfs.erofs "${_erofs_args[@]}" "$_img" "$initdir" &> /dev/null; then
        dfatal "Failed making squash image"
        exit 1
    fi
}

install() {
    if [[ $DRACUT_SQUASH_POST_INST ]]; then
        erofs_installpost
    else
        dstdir="$squashdir" erofs_install
    fi
}

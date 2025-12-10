#!/bin/bash

check() {
    require_kernel_modules overlay || return 1
    return 255
}

depends() {
    echo base
}

installkernel() {
    hostonly="" instmods overlay
}

install() {
    inst_hook cmdline 30 "$moddir/parse-overlayfs.sh"
    inst_hook pre-udev 25 "$moddir/create-overlay-genrules.sh"
    inst_hook pre-mount 01 "$moddir/prepare-overlayfs.sh"
    inst_hook mount 01 "$moddir/mount-overlayfs.sh"     # overlay on top of block device
    inst_hook pre-pivot 10 "$moddir/mount-overlayfs.sh" # overlay on top of network device (e.g. nfs)

    # Install create-overlay script if dmsquash-live-autooverlay is not included
    if ! dracut_module_included "dmsquash-live-autooverlay"; then
        if [ -f "$dracutbasedir/modules.d/70dmsquash-live-autooverlay/create-overlay.sh" ]; then
            inst_script "$dracutbasedir/modules.d/70dmsquash-live-autooverlay/create-overlay.sh" "/sbin/create-overlay"
        fi
    fi
}

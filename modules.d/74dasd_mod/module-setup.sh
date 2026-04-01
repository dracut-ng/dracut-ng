#!/bin/bash

# called by dracut
check() {
    [ "$DRACUT_ARCH" = "s390" ] || [ "$DRACUT_ARCH" = "s390x" ] || return 1
    return 0
}

# called by dracut
installkernel() {
    instmods dasd_mod dasd_eckd_mod dasd_fba_mod dasd_diag_mod
}

# called by dracut
install() {
    inst_hook cmdline 31 "$moddir/parse-dasd-mod.sh"
    inst_multiple -o dasd_cio_free
}

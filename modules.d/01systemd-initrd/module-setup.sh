#!/bin/bash

# called by dracut
check() {
    [[ $mount_needs ]] && return 1

    # Return 255 to only include the module, if another module requires it.
    return 255
}

# called by dracut
depends() {
    echo systemd-udevd systemd-journald systemd-tmpfiles
}

# called by dracut
install() {
    inst_multiple -o \
        "$systemdsystemunitdir"/initrd.target \
        "$systemdsystemunitdir"/initrd-fs.target \
        "$systemdsystemunitdir"/initrd-root-device.target \
        "$systemdsystemunitdir"/initrd-root-fs.target \
        "$systemdsystemunitdir"/initrd-usr-fs.target \
        "$systemdsystemunitdir"/initrd-switch-root.target \
        "$systemdsystemunitdir"/initrd-switch-root.service \
        "$systemdsystemunitdir"/initrd-cleanup.service \
        "$systemdsystemunitdir"/initrd-udevadm-cleanup-db.service \
        "$systemdsystemunitdir"/initrd-parse-etc.service
}

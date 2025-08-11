#!/bin/bash

set -e

# do some sanity checks first
[ -e /run/initramfs/bin/sh ] && exit 0
[ -e /run/initramfs/.need_shutdown ] || exit 0

# SIGTERM signal is received upon forced shutdown: ignore the signal
# We want to remain alive to be able to trap unpacking errors to avoid
# switching root to an incompletely unpacked initramfs
trap 'echo "Received SIGTERM signal, ignoring!" >&2' TERM

KERNEL_VERSION="$(uname -r)"

[[ $dracutbasedir ]] || dracutbasedir=/usr/lib/dracut
SKIP="$dracutbasedir/skipcpio"
[[ -x $SKIP ]] || SKIP="cat"

find_initrd_for_kernel_version() {
    local kernel_version="$1"
    local base_path files initrd machine_id

    if [[ -d /efi/Default ]] || [[ -d /boot/Default ]] || [[ -d /boot/efi/Default ]]; then
        machine_id="Default"
    elif [[ -s /etc/machine-id ]]; then
        read -r machine_id < /etc/machine-id
        [[ $machine_id == "uninitialized" ]] && machine_id="Default"
    else
        machine_id="Default"
    fi

    if [ -n "$machine_id" ]; then
        for base_path in /efi /boot /boot/efi; do
            initrd="${base_path}/${machine_id}/${kernel_version}/initrd"
            if [ -f "$initrd" ]; then
                echo "$initrd"
                return
            fi
        done
    fi

    if [[ -f /lib/modules/${kernel_version}/initrd ]]; then
        echo "/lib/modules/${kernel_version}/initrd"
    elif [[ -f /boot/initramfs-${kernel_version}.img ]]; then
        echo "/boot/initramfs-${kernel_version}.img"
    else
        files=(/boot/initr*"${kernel_version}"*)
        if [ "${#files[@]}" -ge 1 ] && [ -e "${files[0]}" ]; then
            echo "${files[0]}"
        fi
    fi
}

mount -o ro /boot &> /dev/null || true

IMG=$(find_initrd_for_kernel_version "$KERNEL_VERSION")
if [ -z "$IMG" ]; then
    if [[ -f /boot/initramfs-linux.img ]]; then
        IMG="/boot/initramfs-linux.img"
    elif [[ -f /boot/initrd.img ]]; then
        IMG="/boot/initrd.img"
    elif [[ -f /initrd.img ]]; then
        IMG="/initrd.img"
    else
        echo "No initramfs image found to restore!"
        exit 1
    fi
fi

cd /run/initramfs

decompress_unpack() {
    for command in zcat bzcat xzcat lz4 lzop zstd; do
        if command -v "$command" > /dev/null; then
            if "$command" -d -c < "$1" 2> /dev/null | cpio -id --no-absolute-filenames --quiet > /dev/null 2>&1; then
                did_decompress=1
                return 0
            fi
        fi
        cpio -id --no-absolute-filenames --quiet < "$1" > /dev/null 2>&1 && return 0
    done
}

unpack() {
    local did_decompress=0
    $SKIP "$IMG" 2> /dev/null > /tmp/initramfs-restore-cpio.$$
    decompress_unpack /tmp/initramfs-restore-cpio.$$

    # Check for a second layer if this layer is not compressed
    if ((did_decompress)) || [ "$SKIP" == "cat" ]; then
        rm -f -- /tmp/initramfs-restore-cpio.$$
        return
    fi
    $SKIP /tmp/initramfs-restore-cpio.$$ 2> /dev/null > /tmp/initramfs-restore-cpio2.$$
    rm -f -- /tmp/initramfs-restore-cpio.$$
    decompress_unpack /tmp/initramfs-restore-cpio2.$$
    rm -f -- /tmp/initramfs-restore-cpio2.$$
}

if unpack; then
    rm -f -- .need_shutdown
else
    # something failed, so we clean up
    echo "Unpacking of $IMG to /run/initramfs failed" >&2
    rm -f -- /run/initramfs/shutdown
    exit 1
fi

if [[ -f squashfs-root.img ]]; then
    if ! unsquashfs -no-xattrs -f -d . squashfs-root.img > /dev/null; then
        echo "Squash module is enabled for this initramfs but failed to unpack squash-root.img" >&2
        rm -f -- /run/initramfs/shutdown
        exit 1
    fi
elif [[ -f erofs-root.img ]]; then
    if ! fsck.erofs --extract=. --overwrite erofs-root.img > /dev/null; then
        echo "Squash module is enabled for this initramfs but failed to unpack erofs-root.img" >&2
        rm -f -- /run/initramfs/shutdown
        exit 1
    fi
fi

if grep -q -w selinux /sys/kernel/security/lsm 2> /dev/null \
    && [ -e /etc/selinux/config ] && [ -x /usr/sbin/setfiles ]; then
    . /etc/selinux/config
    if [[ $SELINUX != "disabled" && -n $SELINUXTYPE ]]; then
        /usr/sbin/setfiles -v -r /run/initramfs /etc/selinux/"${SELINUXTYPE}"/contexts/files/file_contexts /run/initramfs > /dev/null
    fi
fi

exit 0

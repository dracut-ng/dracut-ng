#!/bin/sh
set -eu

# required binaries: cat grep

check_crypt_mounted() {
    if ! grep -q "^/dev/mapper/overlay-crypt /run/overlayfs-backing " /proc/mounts; then
        echo "encrypted overlay not mounted at /run/overlayfs-backing" >> /run/failed
    fi
}

check_crypt_device() {
    local _dm
    for _dm in /sys/class/block/dm-*; do
        if [ "$(cat "$_dm/dm/name" 2> /dev/null)" = "overlay-crypt" ]; then
            grep -q "^CRYPT-" "$_dm/dm/uuid" 2> /dev/null && return 0
            break
        fi
    done
    echo "overlay-crypt is not a dm-crypt device" >> /run/failed
}

check_crypt_passphrase() {
    if [ ! -f /run/initramfs/overlayfs.passwd ]; then
        echo "password file /run/initramfs/overlayfs.passwd not found" >> /run/failed
    fi
}

if grep -q 'test.expect=none' /proc/cmdline; then
    if grep -q " overlay " /proc/mounts; then
        echo "overlay filesystem found in /proc/mounts" >> /run/failed
    fi
else
    if ! grep -q " overlay " /proc/mounts; then
        echo "overlay filesystem not found in /proc/mounts" >> /run/failed
    fi

    if ! echo > /test-overlay-write; then
        echo "overlay is not writable" >> /run/failed
    fi
fi

if grep -q 'test.expect=device' /proc/cmdline; then
    if ! grep -q "/run/overlayfs-backing" /proc/mounts; then
        echo "persistent overlay device not mounted at /run/overlayfs-backing" >> /run/failed
    fi
elif grep -q 'test.expect=crypt' /proc/cmdline; then
    check_crypt_mounted
    check_crypt_device
    check_crypt_passphrase
else
    if grep -q "/run/overlayfs-backing" /proc/mounts; then
        echo "persistent overlay device is mounted at /run/overlayfs-backing" >> /run/failed
    fi
fi

if grep -q 'test.expect=tmpfs-sized' /proc/cmdline; then
    if ! grep -q "^tmpfs /run/initramfs/overlay tmpfs " /proc/mounts; then
        echo "sized tmpfs not mounted at /run/initramfs/overlay" >> /run/failed
    fi
    if ! grep -q "^tmpfs /run/initramfs/overlay tmpfs .*size=32768k" /proc/mounts; then
        echo "sized tmpfs does not have expected size (32M)" >> /run/failed
    fi
    if ! grep -q "^tmpfs /run/initramfs/overlay tmpfs .*nr_inodes=100000" /proc/mounts; then
        echo "sized tmpfs does not have expected nr_inodes (100000)" >> /run/failed
    fi
fi

# Dump /proc/mounts at the end if there were any failures for easier debugging
if [ -s /run/failed ]; then
    {
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> /proc/mounts >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        cat /proc/mounts
        echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< /proc/mounts <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
    } >> /run/failed
fi

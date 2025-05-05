#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# keep this module as small as possible and consider adding rules to more
# specific dracut modules when possible

# Prerequisite check(s) for module.
check() {
    [[ $mount_needs ]] && return 1
    # If the binary(s) requirements are not fulfilled the module can't be installed
    require_binaries "$systemdutildir"/systemd || return 1
    # Return 255 to only include the module, if another module requires it.
    return 255
}

# Config adjustments before installing anything.
config() {
    add_dlopen_features+=" libsystemd-shared-*.so:kmod "
}

installkernel() {
    hostonly='' instmods autofs4 ipv6 dmi-sysfs
    hostonly=$(optional_hostonly) instmods -s efivarfs
}

# called by dracut
install() {

    if [[ $prefix == /run/* ]]; then
        dfatal 'systemd does not work with a prefix, which contains "/run"!!'
        exit 1
    fi

    inst_multiple -o \
        "$systemdutildir"/systemd \
        "$systemdutildir"/systemd-coredump \
        "$systemdutildir"/systemd-cgroups-agent \
        "$systemdutildir"/systemd-executor \
        "$systemdutildir"/systemd-shutdown \
        "$systemdutildir"/systemd-reply-password \
        "$systemdutildir"/systemd-fsck \
        "$systemdutildir"/systemd-validatefs \
        "$systemdutildir"/systemd-volatile-root \
        "$systemdutildir"/systemd-sysroot-fstab-check \
        "$systemdutildir"/system-generators/systemd-debug-generator \
        "$systemdutildir"/system-generators/systemd-fstab-generator \
        "$systemdutildir"/system-generators/systemd-gpt-auto-generator \
        "$systemdutildir"/system.conf \
        "$systemdutildir"/system.conf.d/*.conf \
        "$systemdsystemunitdir"/debug-shell.service \
        "$systemdsystemunitdir"/emergency.target \
        "$systemdsystemunitdir"/sysinit.target \
        "$systemdsystemunitdir"/basic.target \
        "$systemdsystemunitdir"/halt.target \
        "$systemdsystemunitdir"/kexec.target \
        "$systemdsystemunitdir"/local-fs.target \
        "$systemdsystemunitdir"/local-fs-pre.target \
        "$systemdsystemunitdir"/remote-fs.target \
        "$systemdsystemunitdir"/remote-fs-pre.target \
        "$systemdsystemunitdir"/multi-user.target \
        "$systemdsystemunitdir"/network.target \
        "$systemdsystemunitdir"/network-pre.target \
        "$systemdsystemunitdir"/network-online.target \
        "$systemdsystemunitdir"/nss-lookup.target \
        "$systemdsystemunitdir"/nss-user-lookup.target \
        "$systemdsystemunitdir"/poweroff.target \
        "$systemdsystemunitdir"/reboot.target \
        "$systemdsystemunitdir"/rescue.target \
        "$systemdsystemunitdir"/rpcbind.target \
        "$systemdsystemunitdir"/shutdown.target \
        "$systemdsystemunitdir"/final.target \
        "$systemdsystemunitdir"/sigpwr.target \
        "$systemdsystemunitdir"/sockets.target \
        "$systemdsystemunitdir"/swap.target \
        "$systemdsystemunitdir"/timers.target \
        "$systemdsystemunitdir"/paths.target \
        "$systemdsystemunitdir"/umount.target \
        "$systemdsystemunitdir"/sys-kernel-config.mount \
        "$systemdsystemunitdir"/systemd-halt.service \
        "$systemdsystemunitdir"/systemd-poweroff.service \
        "$systemdsystemunitdir"/systemd-reboot.service \
        "$systemdsystemunitdir"/systemd-kexec.service \
        "$systemdsystemunitdir"/systemd-fsck@.service \
        "$systemdsystemunitdir"/systemd-validatefs@.service \
        "$systemdsystemunitdir"/systemd-volatile-root.service \
        "$systemdsystemunitdir"/ctrl-alt-del.target \
        "$systemdsystemunitdir"/syslog.socket \
        "$systemdsystemunitdir"/slices.target \
        "$systemdsystemunitdir"/system.slice \
        "$systemdsystemunitdir"/-.slice \
        systemctl \
        echo swapoff \
        chmod \
        mount umount reboot poweroff \
        systemd-run systemd-escape \
        systemd-cgls

    if [[ $hostonly ]]; then
        inst_multiple -H -o \
            "$systemdutilconfdir"/system.conf \
            "$systemdutilconfdir"/system.conf.d/*.conf \
            /etc/hosts \
            /etc/hostname \
            /etc/nsswitch.conf \
            /etc/machine-id \
            /etc/machine-info
    fi

    if ! [[ -e "$initdir/etc/machine-id" ]]; then
        : > "$initdir/etc/machine-id"
        chmod 444 "$initdir/etc/machine-id"
    fi

    inst_multiple -o nologin
    {
        grep '^adm:' "$dracutsysrootdir"/etc/passwd 2> /dev/null
        # we don't use systemd-networkd, but the user is in systemd.conf tmpfiles snippet
        grep '^systemd-network:' "$dracutsysrootdir"/etc/passwd 2> /dev/null
    } >> "$initdir/etc/passwd"

    {
        grep '^wheel:' "$dracutsysrootdir"/etc/group 2> /dev/null
        grep '^adm:' "$dracutsysrootdir"/etc/group 2> /dev/null
        grep '^utmp:' "$dracutsysrootdir"/etc/group 2> /dev/null
        grep '^root:' "$dracutsysrootdir"/etc/group 2> /dev/null
        # we don't use systemd-networkd, but the user is in systemd.conf tmpfiles snippet
        grep '^systemd-network:' "$dracutsysrootdir"/etc/group 2> /dev/null
    } >> "$initdir/etc/group"

    local _systemdbinary="$systemdutildir"/systemd

    # testing systemd using sanitizers - see https://systemd.io/TESTING_WITH_SANITIZERS/
    if ldd "$_systemdbinary" | grep -qw libasan; then
        local _wrapper="$systemdutildir"/systemd-asan-wrapper
        cat > "$initdir"/"$_wrapper" << EOF
#!/bin/sh
mount -t proc -o nosuid,nodev,noexec proc /proc
exec $_systemdbinary
EOF
        chmod 755 "$initdir"/"$_wrapper"
        _systemdbinary="$_wrapper"
        unset _wrapper
    fi
    ln_r "$_systemdbinary" "/init"

    unset _systemdbinary

    # Install library file(s)
    _arch=${DRACUT_ARCH:-$(uname -m)}
    inst_libdir_file \
        {"tls/$_arch/",tls/,"$_arch/",}"libbpf.so*" \
        {"tls/$_arch/",tls/,"$_arch/",}"libnss_*"
}

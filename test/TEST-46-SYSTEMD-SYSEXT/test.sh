#!/usr/bin/env bash
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on a ext4 filesystem with systemd and extensions"

# Uncomment these to debug failures
#DEBUGFAIL="systemd.show_status=1 systemd.log_level=debug"

test_check() {
    local binary

    for binary in systemd-repart openssl; do
        if ! type -p "$binary" &> /dev/null; then
            echo "Test needs $binary... Skipping"
            return 1
        fi
    done
}

test_run() {
    declare -a disk_args=()
    qemu_add_drive disk_args "$TESTDIR"/root.img root

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=LABEL=dracut $TEST_KERNEL_CMDLINE" \
        -initrd "$TESTDIR"/initramfs.testing

    # Check if the message "All OK" is in QEMU logs
    check_qemu_log

    # Also check if the message "dracut-sysext-success" is in QEMU logs
    check_qemu_log "$QEMU_LOGFILE" "dracut-sysext-success"
}

test_setup() {
    local crt_dir confext_name sysext_name

    # Create plain root filesystem
    build_client_rootfs "$TESTDIR/rootfs"

    # Create an ext4 image with the rootfs
    build_ext4_image "$TESTDIR/rootfs" "$TESTDIR/root.img" dracut

    # Create X.509 certificate to sign extensions
    crt_dir="dracut-crt"
    mkdir -p "$TESTDIR/$crt_dir"
    pushd "$TESTDIR/$crt_dir"
    cat > "dracut.cnf" << EOF
[req]
prompt = no
distinguished_name = dracut_distinguished_name
[dracut_distinguished_name]
C = ES
ST = State
L = Locality
O = Org
OU = Org Unit
CN = Common Name
emailAddress = dracut@example.com
EOF
    openssl req \
        -config "dracut.cnf" \
        -new -x509 \
        -newkey rsa:1024 \
        -keyout "dracut.key" \
        -out "dracut.crt" \
        -days 365 \
        -nodes
    popd

    # Create a configuration extension: it simply creates a marker in /etc
    confext_name="dracut-confext"
    mkdir -p "$TESTDIR/$confext_name/etc/extension-release.d"
    pushd "$TESTDIR/$confext_name/etc"
    echo "dracut-sysext-success" > "$confext_name.marker"
    {
        grep -e "^ID=" -e "^VERSION_ID=" /etc/os-release
        echo "CONFEXT_SCOPE=initrd"
    } > "extension-release.d/extension-release.$confext_name"
    popd
    # systemd-repart creates erofs partitions by default: override it to use
    # a more widely supported format like squashfs
    SYSTEMD_REPART_OVERRIDE_FSTYPE=squashfs systemd-repart \
        --make-ddi=confext \
        --private-key="$TESTDIR/$crt_dir/dracut.key" \
        --certificate="$TESTDIR/$crt_dir/dracut.crt" \
        --copy-source="$TESTDIR/$confext_name" \
        "$TESTDIR/$confext_name.raw"

    # Create a system extension: this will create a script in
    # initqueue/finished that checks if the marker created with the confext
    # exists and prints its content (if this check fails, the initqueue loop
    # will not end and the system will not boot)
    sysext_name="dracut-sysext"
    mkdir -p "$TESTDIR/$sysext_name/usr/lib/dracut/hooks/initqueue/finished"
    pushd "$TESTDIR/$sysext_name/usr/lib"
    touch "dracut/hooks/initqueue/finished/$sysext_name.sh"
    chmod +x "dracut/hooks/initqueue/finished/$sysext_name.sh"
    echo "[ -e \"/etc/$confext_name.marker\" ] && warn \"\$(cat /etc/$confext_name.marker)\"" > "dracut/hooks/initqueue/finished/$sysext_name.sh"
    mkdir -p "extension-release.d"
    {
        grep -e "^ID=" -e "^VERSION_ID=" /etc/os-release
        echo "SYSEXT_SCOPE=initrd"
    } > "extension-release.d/extension-release.$sysext_name"
    popd
    # systemd-repart creates erofs partitions by default: override it to use
    # a more widely supported format like squashfs
    SYSTEMD_REPART_OVERRIDE_FSTYPE=squashfs systemd-repart \
        --make-ddi=sysext \
        --private-key="$TESTDIR/$crt_dir/dracut.key" \
        --certificate="$TESTDIR/$crt_dir/dracut.crt" \
        --copy-source="$TESTDIR/$sysext_name" \
        "$TESTDIR/$sysext_name.raw"

    # "Simulate" that the bootloader copies the extensions in /.extra
    # We also need to copy the public certificate to allow userspace verity
    # signature checking
    test_dracut \
        --no-hostonly-cmdline \
        -i "$TESTDIR/$confext_name.raw" "/.extra/confext/$confext_name.raw" \
        -i "$TESTDIR/$sysext_name.raw" "/.extra/sysext/$sysext_name.raw" \
        -i "$TESTDIR/$crt_dir/dracut.crt" "/etc/verity.d/dracut.crt" \
        -a "systemd-sysext initqueue"
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

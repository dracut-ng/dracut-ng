#!/usr/bin/env bash
set -eu

[ -z "${USE_NETWORK-}" ] && USE_NETWORK="network"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on NBD with $USE_NETWORK"

# Uncomment this to debug failures
# DEBUGFAIL="rd.debug systemd.log_target=console loglevel=7"
#DEBUGFAIL="rd.shell rd.break rd.debug systemd.log_target=console loglevel=7 systemd.log_level=debug"
#SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="tcp:127.0.0.1:9999"

test_check() {
    if ! type -p nbd-server &> /dev/null; then
        echo "Test needs nbd-server... Skipping"
        return 1
    fi

    return 0
}

run_server() {
    # Start server first
    echo "NBD TEST SETUP: Starting DHCP/NBD server"

    declare -a disk_args=()
    qemu_add_drive disk_args "$TESTDIR"/unencrypted.img unencrypted
    qemu_add_drive disk_args "$TESTDIR"/encrypted.img encrypted
    qemu_add_drive disk_args "$TESTDIR"/server.img serverroot

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -net nic,macaddr=52:54:00:12:34:56,model=virtio \
        -net socket,listen=127.0.0.1:12340 \
        -append "panic=1 oops=panic softlockup_panic=1 rd.luks=0 systemd.crash_reboot quiet root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_serverroot rootfstype=ext4 rw systemd.journald.forward_to_console=1 ${SERVER_DEBUG-}" \
        -pidfile "$TESTDIR"/server.pid -daemonize \
        -initrd "$TESTDIR"/initramfs.server
    chmod 644 "$TESTDIR"/server.pid

    if ! [[ ${SERIAL-} ]]; then
        wait_for_server_startup
    else
        echo Sleeping 10 seconds to give the server a head start
        sleep 10
    fi
}

client_test() {
    local test_name="$1"
    local mac=$2
    local cmdline="$3"
    local fstype=${4-ext4}
    local fsopt=${5-ro}
    local found opts nbdinfo

    client_test_start "$test_name"

    declare -a disk_args=()
    qemu_add_drive disk_args "$TESTDIR"/marker.img marker

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net nic,macaddr="$mac",model=virtio \
        -net socket,connect=127.0.0.1:12340 \
        -append "$cmdline rd.auto ro" \
        -initrd "$TESTDIR"/initramfs.testing

    if ! test_marker_check nbd-OK; then
        client_test_end "FAILED - MISSING MARKER"
        return 1
    fi

    # nbdinfo=( fstype fsoptions )
    read -r -a nbdinfo < <(awk '{print $2, $3; exit}' "$TESTDIR"/marker.img)

    if [[ ${nbdinfo[0]} != "$fstype" ]]; then
        client_test_end "FAILED - WRONG FS TYPE: \"${nbdinfo[0]}\" != \"$fstype\""
        return 1
    fi

    opts=${nbdinfo[1]},
    while [[ $opts ]]; do
        if [[ ${opts%%,*} == "$fsopt" ]]; then
            found=1
            break
        fi
        opts=${opts#*,}
    done

    if [[ ! $found ]]; then
        client_test_end "FAILED - BAD FS OPTS: \"${nbdinfo[1]}\" != \"$fsopt\""
        return 1
    fi

    client_test_end
}

test_run() {
    if ! run_server; then
        echo "Failed to start server" 1>&2
        return 1
    fi
    client_run
    local res="$?"
    kill_server
    return "$res"
}

client_run() {
    # The default is ext4,errors=continue so use that to determine
    # if our options were parsed and used
    client_test "NBD root=nbd:IP:port" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw rd.luks=0"

    client_test "NBD root=nbd:IP:port::fsopts" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw::errors=panic rd.luks=0" \
        ext4 errors=panic

    client_test "NBD root=nbd:IP:port:fstype" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw:ext4 rd.luks=0" ext4

    client_test "NBD root=nbd:IP:port:fstype:fsopts" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw:ext4:errors=panic rd.luks=0" \
        ext4 errors=panic

    # DHCP root-path parsing

    client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port" 52:54:00:12:34:01 \
        "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0"

    # BROKEN
    #client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port:fstype" \
    #    52:54:00:12:34:02 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext2

    client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port::fsopts" \
        52:54:00:12:34:03 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext4 errors=panic

    # BROKEN
    #client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port:fstype:fsopts" \
    #    52:54:00:12:34:04 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext2 errors=panic

    # netroot handling

    client_test "NBD netroot=nbd:IP:port" 52:54:00:12:34:00 \
        "root=LABEL=dracut netroot=nbd:192.168.50.1:raw ip=dhcp rd.luks=0"

    # Encrypted root handling via LVM/LUKS over NBD

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    client_test "NBD root=LABEL=dracut netroot=nbd:IP:port" \
        52:54:00:12:34:00 \
        "root=LABEL=dracut rd.luks.uuid=$ID_FS_UUID rd.lv.vg=dracut ip=dhcp netroot=nbd:192.168.50.1:encrypted"

    # XXX This should be ext4,errors=panic but that doesn't currently
    # XXX work when you have a real root= line in addition to netroot=
    # XXX How we should work here needs clarification
    #    client_test "NBD root=LABEL=dracut netroot=dhcp (w/ fstype and opts)" \
    #                52:54:00:12:34:05 \
    #                "root=LABEL=dracut rd.luks.uuid=$ID_FS_UUID rd.lv.vg=dracut netroot=dhcp"

    if [[ -s server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

}

make_encrypted_rootfs() {
    rm -fr "$TESTDIR"/overlay
    # Create what will eventually be our root filesystem onto an overlay
    build_client_rootfs "$TESTDIR/overlay/source"
    inst_multiple ip grep
    inst_init ./client-init.sh "$TESTDIR"/overlay/source

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    call_dracut -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "crypt lvm mdraid" \
        -I "cryptsetup" \
        -i ./create-encrypted-root.sh /usr/lib/dracut/hooks/initqueue/01-create-encrypted-root.sh \
        -f "$TESTDIR"/initramfs.makeroot
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    qemu_add_drive disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_args "$TESTDIR"/encrypted.img root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw quiet" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created
    grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img > "$TESTDIR"/luks.uuid
}

make_client_rootfs() {
    build_client_rootfs "$TESTDIR/client-rootfs"
    inst_multiple ip
    inst_init ./client-init.sh "$TESTDIR"/client-rootfs

    build_ext4_image "$TESTDIR/client-rootfs" "$TESTDIR"/unencrypted.img dracut
    rm -fr "$TESTDIR"/client-rootfs
}

make_server_rootfs() {
    rm -fr "$TESTDIR"/server-rootfs

    cat > /tmp/config << EOF
[generic]
[raw]
exportname = /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_unencrypted
port = 2000
bs = 4096
[encrypted]
exportname = /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_encrypted
port = 2001
bs = 4096
EOF

    call_dracut --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a "$USE_NETWORK" \
        -I "ip grep sleep nbd-server chmod modprobe pidof" \
        --install-optional "/etc/netconfig dhcpd /etc/group /etc/nsswitch.conf /etc/rpc /etc/protocols /etc/services /usr/etc/nsswitch.conf /usr/etc/rpc /usr/etc/protocols /usr/etc/services" \
        -i /tmp/config /etc/nbd-server/config \
        -i "./dhcpd.conf" "/etc/dhcpd.conf" \
        --no-hostonly \
        -f "$TESTDIR"/initramfs.root
    mkdir -p "$TESTDIR"/server-rootfs
    mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/server-rootfs
    rm -rf "$TESTDIR"/dracut.*

    mkdir -p -- "$TESTDIR"/server-rootfs/var/lib/dhcpd "$TESTDIR"/server-rootfs/etc/nbd-server
    inst_init ./server-init.sh "$TESTDIR"/server-rootfs

    build_ext4_image "$TESTDIR/server-rootfs" "$TESTDIR"/server.img dracut
    rm -fr "$TESTDIR"/server-rootfs
}

test_setup() {
    make_encrypted_rootfs
    make_client_rootfs
    make_server_rootfs

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    echo "luks-$ID_FS_UUID /dev/nbd0 /etc/key" > /tmp/crypttab
    echo -n test > /tmp/key

    test_dracut \
        --no-hostonly \
        -a "watchdog ${USE_NETWORK}" \
        -i "./client.link" "/etc/systemd/network/01-client.link" \
        -i "/tmp/crypttab" "/etc/crypttab" \
        -i "/tmp/key" "/etc/key"

    call_dracut -N \
        --add-confdir test \
        -a "$USE_NETWORK ${SERVER_DEBUG:+debug}" \
        -i "./server.link" "/etc/systemd/network/01-server.link" \
        -i "./wait-if-server.sh" "/usr/lib/dracut/hooks/pre-mount/99-wait-if-server.sh" \
        -f "$TESTDIR"/initramfs.server
}

kill_server() {
    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

test_cleanup() {
    kill_server
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

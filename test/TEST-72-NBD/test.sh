#!/usr/bin/env bash

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on NBD with $USE_NETWORK"

# Uncomment this to debug failures
# DEBUGFAIL="rd.debug systemd.log_target=console loglevel=7"
#DEBUGFAIL="rd.shell rd.break rd.debug systemd.log_target=console loglevel=7 systemd.log_level=debug"
#SERIAL="tcp:127.0.0.1:9999"

test_check() {
    if ! type -p dhclient &> /dev/null; then
        echo "Test needs dhclient for server networking... Skipping"
        return 1
    fi

    if ! type -p nbd-server &> /dev/null; then
        echo "Test needs nbd-server... Skipping"
        return 1
    fi

    if ! modinfo -k "$KVERSION" nbd &> /dev/null; then
        echo "Kernel module nbd does not exist"
        return 1
    fi

    return 0
}

run_server() {
    # Start server first
    echo "NBD TEST SETUP: Starting DHCP/NBD server"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/unencrypted.img unencrypted
    qemu_add_drive disk_index disk_args "$TESTDIR"/encrypted.img encrypted
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img serverroot

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -net nic,macaddr=52:54:00:12:34:56,model=e1000 \
        -net socket,listen=127.0.0.1:12340 \
        -append "panic=1 oops=panic softlockup_panic=1 rd.luks=0 systemd.crash_reboot quiet root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_serverroot rootfstype=ext4 rw console=ttyS0,115200n81 $SERVER_DEBUG" \
        -initrd "$TESTDIR"/initramfs.server \
        -pidfile "$TESTDIR"/server.pid -daemonize || return 1
    chmod 644 "$TESTDIR"/server.pid || return 1

    # Cleanup the terminal if we have one
    tty -s && stty sane

    if ! [[ $SERIAL ]]; then
        echo "Waiting for the server to startup"
        while :; do
            grep Serving "$TESTDIR"/server.log && break
            tail "$TESTDIR"/server.log
            sleep 1
        done
    else
        echo Sleeping 10 seconds to give the server a head start
        sleep 10
    fi
}

client_test() {
    local test_name="$1"
    local mac=$2
    local cmdline="$3"
    local fstype=$4
    local fsopt=$5
    local found opts nbdinfo

    [[ $fstype ]] || fstype=ext4
    [[ $fsopt ]] || fsopt="ro"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net nic,macaddr="$mac",model=e1000 \
        -net socket,connect=127.0.0.1:12340 \
        -append "$cmdline rd.auto ro console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.testing

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] || ! test_marker_check nbd-OK; then
        echo "CLIENT TEST END: $test_name [FAILED - BAD EXIT]"
        return 1
    fi

    # nbdinfo=( fstype fsoptions )
    read -r -a nbdinfo < <(awk '{print $2, $3; exit}' "$TESTDIR"/marker.img)

    if [[ ${nbdinfo[0]} != "$fstype" ]]; then
        echo "CLIENT TEST END: $test_name [FAILED - WRONG FS TYPE] \"${nbdinfo[0]}\" != \"$fstype\""
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
        echo "CLIENT TEST END: $test_name [FAILED - BAD FS OPTS] \"${nbdinfo[1]}\" != \"$fsopt\""
        return 1
    fi

    echo "CLIENT TEST END: $test_name [OK]"
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
        "root=nbd:192.168.50.1:raw rd.luks=0" || return 1

    client_test "NBD root=nbd:IP:port::fsopts" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw::errors=panic rd.luks=0" \
        ext4 errors=panic || return 1

    client_test "NBD root=nbd:IP:port:fstype" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw:ext4 rd.luks=0" ext4 || return 1

    client_test "NBD root=nbd:IP:port:fstype:fsopts" 52:54:00:12:34:00 \
        "root=nbd:192.168.50.1:raw:ext4:errors=panic rd.luks=0" \
        ext4 errors=panic || return 1

    # DHCP root-path parsing

    client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port" 52:54:00:12:34:01 \
        "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" || return 1

    # BROKEN
    #client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port:fstype" \
    #    52:54:00:12:34:02 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext2 || return 1

    client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port::fsopts" \
        52:54:00:12:34:03 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext4 errors=panic || return 1

    # BROKEN
    #client_test "NBD root=/dev/root netroot=dhcp DHCP root-path nbd:srv:port:fstype:fsopts" \
    #    52:54:00:12:34:04 "root=/dev/root netroot=dhcp ip=dhcp rd.luks=0" ext2 errors=panic || return 1

    # netroot handling

    client_test "NBD netroot=nbd:IP:port" 52:54:00:12:34:00 \
        "root=LABEL=dracut netroot=nbd:192.168.50.1:raw ip=dhcp rd.luks=0" || return 1

    # Encrypted root handling via LVM/LUKS over NBD

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    client_test "NBD root=LABEL=dracut netroot=nbd:IP:port" \
        52:54:00:12:34:00 \
        "root=LABEL=dracut rd.luks.uuid=$ID_FS_UUID rd.lv.vg=dracut ip=dhcp netroot=nbd:192.168.50.1:encrypted" || return 1

    # XXX This should be ext4,errors=panic but that doesn't currently
    # XXX work when you have a real root= line in addition to netroot=
    # XXX How we should work here needs clarification
    #    client_test "NBD root=LABEL=dracut netroot=dhcp (w/ fstype and opts)" \
    #                52:54:00:12:34:05 \
    #                "root=LABEL=dracut rd.luks.uuid=$ID_FS_UUID rd.lv.vg=dracut netroot=dhcp" || return 1

    if [[ -s server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

}

make_encrypted_root() {
    rm -fr "$TESTDIR"/overlay
    # Create what will eventually be our root filesystem onto an overlay
    "$DRACUT" -l --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -I "ip grep" \
        --no-hostonly --no-hostonly-cmdline --nohardlink \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*
    cp ./client-init.sh "$TESTDIR"/overlay/source/sbin/init

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -l -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "crypt lvm mdraid" \
        -I "cryptsetup" \
        -i ./create-encrypted-root.sh /lib/dracut/hooks/initqueue/01-create-encrypted-root.sh \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/encrypted.img root 120

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    grep -F -a -m 1 ID_FS_UUID "$TESTDIR"/marker.img > "$TESTDIR"/luks.uuid
}

make_client_root() {
    rm -fr "$TESTDIR"/overlay
    "$DRACUT" -l --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -I "ip" \
        --no-hostonly --no-hostonly-cmdline --nohardlink \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*
    cp ./client-init.sh "$TESTDIR"/overlay/source/sbin/init

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -l -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -i ./create-client-root.sh /lib/dracut/hooks/initqueue/01-create-client-root.sh \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/unencrypted.img root 120

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    rm -fr "$TESTDIR"/overlay
}

make_server_root() {
    rm -fr "$TESTDIR"/overlay

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

    "$DRACUT" -l --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a "network-legacy" \
        -I "ip grep sleep nbd-server chmod modprobe vi pidof" \
        --install-optional "/etc/netconfig dhcpd /etc/group /etc/nsswitch.conf /etc/rpc /etc/protocols /etc/services /usr/etc/nsswitch.conf /usr/etc/rpc /usr/etc/protocols /usr/etc/services" \
        -i /tmp/config /etc/nbd-server/config \
        -i "./dhcpd.conf" "/etc/dhcpd.conf" \
        --no-hostonly --no-hostonly-cmdline --nohardlink \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1
    mkdir -p "$TESTDIR"/overlay/source && mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source && rm -rf "$TESTDIR"/dracut.*

    mkdir -p -- "$TESTDIR"/overlay/source/var/lib/dhcpd "$TESTDIR"/overlay/source/etc/nbd-server
    cp ./server-init.sh "$TESTDIR"/overlay/source/sbin/init

    # second, install the files needed to make the root filesystem
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -N -l -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "network-legacy" \
        -i ./create-server-root.sh /lib/dracut/hooks/initqueue/01-create-server-root.sh \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img root 480

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1
    test_marker_check dracut-root-block-created || return 1
    rm -fr "$TESTDIR"/overlay
}

test_setup() {
    make_encrypted_root || return 1
    make_client_root || return 1
    make_server_root || return 1

    rm -fr "$TESTDIR"/overlay
    # Make the test image

    # shellcheck source=$TESTDIR/luks.uuid
    . "$TESTDIR"/luks.uuid

    echo "luks-$ID_FS_UUID /dev/nbd0 /etc/key" > /tmp/crypttab
    echo -n test > /tmp/key

    test_dracut \
        --no-hostonly --no-hostonly-cmdline \
        -a "${USE_NETWORK}" \
        -i "./cryptroot-ask.sh" "/sbin/cryptroot-ask" \
        -i "./client.link" "/etc/systemd/network/01-client.link" \
        -i "/tmp/crypttab" "/etc/crypttab" \
        -i "/tmp/key" "/etc/key" \
        "$TESTDIR"/initramfs.testing

    "$DRACUT" -N -l -i "$TESTDIR"/overlay / \
        -a "test rootfs-block debug kernel-modules network-legacy" \
        -d "af_packet piix ide-gd_mod ata_piix ext4 sd_mod e1000 drbg" \
        -i "./server.link" "/etc/systemd/network/01-server.link" \
        -i "./wait-if-server.sh" "/lib/dracut/hooks/pre-mount/99-wait-if-server.sh" \
        -f "$TESTDIR"/initramfs.server "$KVERSION" || return 1
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

#!/usr/bin/env bash
set -eu

[ -z "${USE_NETWORK-}" ] && USE_NETWORK="network"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on NFS with $USE_NETWORK"

test_check() {
    if ! type -p dhclient &> /dev/null; then
        echo "Test needs dhclient for server networking... Skipping"
        return 1
    fi

    if ! type -p curl &> /dev/null; then
        echo "Test needs curl for url-lib... Skipping"
        return 1
    fi

    command -v exportfs &> /dev/null
}

# Uncomment this to debug failures
#DEBUGFAIL="rd.debug loglevel=7 rd.break=initqueue rd.shell"
#SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="unix:/tmp/server.sock"

run_server() {
    # Start server first
    echo "NFS TEST SETUP: Starting DHCP/NFS server"
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img root 0 1

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net socket,listen=127.0.0.1:12320 \
        -net nic,macaddr=52:54:00:12:34:56,model=virtio \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -append "panic=1 oops=panic softlockup_panic=1 root=LABEL=dracut rootfstype=ext4 rw console=ttyS0,115200n81 ${SERVER_DEBUG-}" \
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
    local server="$4"
    local check_opt="$5"
    local nfsinfo opts found expected

    echo "CLIENT TEST START: $test_name"

    # Need this so kvm-qemu will boot (needs non-/dev/zero local disk)
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker2.img marker2 1
    cmdline="$cmdline rd.net.timeout.dhcp=30"

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net nic,macaddr="$mac",model=virtio \
        -net socket,connect=127.0.0.1:12320 \
        -append "$TEST_KERNEL_CMDLINE $cmdline ro" \
        -initrd "$TESTDIR"/initramfs.testing

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]] || ! test_marker_check nfs-OK; then
        echo "CLIENT TEST END: $test_name [FAILED - BAD EXIT]"
        return 1
    fi

    # nfsinfo=( server:/path nfs{,4} options )
    read -r -a nfsinfo < <(awk '{print $2, $3, $4; exit}' "$TESTDIR"/marker.img)

    if [[ ${nfsinfo[0]%%:*} != "$server" ]]; then
        echo "CLIENT TEST INFO: got server: ${nfsinfo[0]%%:*}"
        echo "CLIENT TEST INFO: expected server: $server"
        echo "CLIENT TEST END: $test_name [FAILED - WRONG SERVER]"
        return 1
    fi

    found=0
    expected=1
    if [[ ${check_opt:0:1} == '-' ]]; then
        expected=0
        check_opt=${check_opt:1}
    fi

    opts=${nfsinfo[2]},
    while [[ $opts ]]; do
        if [[ ${opts%%,*} == "$check_opt" ]]; then
            found=1
            break
        fi
        opts=${opts#*,}
    done

    if [[ $found -ne $expected ]]; then
        echo "CLIENT TEST INFO: got options: ${nfsinfo[2]%%:*}"
        if [[ $expected -eq 0 ]]; then
            echo "CLIENT TEST INFO: did not expect: $check_opt"
            echo "CLIENT TEST END: $test_name [FAILED - UNEXPECTED OPTION]"
        else
            echo "CLIENT TEST INFO: missing: $check_opt"
            echo "CLIENT TEST END: $test_name [FAILED - MISSING OPTION]"
        fi
        return 1
    fi

    if ! test_marker_check nfsfetch-OK marker2.img; then
        echo "CLIENT TEST END: $test_name [FAILED - NFS FETCH FAILED]"
        return 1
    fi

    echo "CLIENT TEST END: $test_name [OK]"
    return 0
}

test_nfsv3() {
    # MAC numbering scheme:
    # NFSv3: last octet starts at 0x00 and works up
    # NFSv4: last octet starts at 0x80 and works up

    client_test "NFSv3 root=dhcp DHCP path only" 52:54:00:12:34:00 \
        "root=dhcp" 192.168.50.1 -wsize=4096

    client_test "NFSv3 Legacy root=/dev/nfs nfsroot=IP:path" 52:54:00:12:34:01 \
        "root=/dev/nfs nfsroot=192.168.50.1:/nfs/client" 192.168.50.1 -wsize=4096

    client_test "NFSv3 Legacy root=/dev/nfs DHCP path only" 52:54:00:12:34:00 \
        "root=/dev/nfs" 192.168.50.1 -wsize=4096

    client_test "NFSv3 Legacy root=/dev/nfs DHCP IP:path" 52:54:00:12:34:01 \
        "root=/dev/nfs" 192.168.50.2 -wsize=4096

    client_test "NFSv3 root=dhcp DHCP IP:path" 52:54:00:12:34:01 \
        "root=dhcp" 192.168.50.2 -wsize=4096

    client_test "NFSv3 root=dhcp DHCP proto:IP:path" 52:54:00:12:34:02 \
        "root=dhcp" 192.168.50.3 -wsize=4096

    client_test "NFSv3 root=dhcp DHCP proto:IP:path:options" 52:54:00:12:34:03 \
        "root=dhcp" 192.168.50.3 wsize=4096

    client_test "NFSv3 root=nfs:..." 52:54:00:12:34:04 \
        "root=nfs:192.168.50.1:/nfs/client" 192.168.50.1 -wsize=4096

    client_test "NFSv3 Bridge root=nfs:..." 52:54:00:12:34:04 \
        "root=nfs:192.168.50.1:/nfs/client bridge net.ifnames=0" 192.168.50.1 -wsize=4096

    client_test "NFSv3 Legacy root=IP:path" 52:54:00:12:34:04 \
        "root=192.168.50.1:/nfs/client" 192.168.50.1 -wsize=4096

    client_test "NFSv3 root=dhcp DHCP path,options" 52:54:00:12:34:05 \
        "root=dhcp" 192.168.50.1 wsize=4096

    client_test "NFSv3 root=dhcp DHCP IP:path,options" 52:54:00:12:34:06 \
        "root=dhcp" 192.168.50.2 wsize=4096

    client_test "NFSv3 root=dhcp DHCP proto:IP:path,options" 52:54:00:12:34:07 \
        "root=dhcp" 192.168.50.3 wsize=4096

    # TODO FIXME
    #    client_test "NFSv3 Bridge Customized root=dhcp DHCP path,options" 52:54:00:12:34:05 \
    #        "root=dhcp bridge=foobr0:enp0s1" 192.168.50.1 wsize=4096

    return 0
}

test_nfsv4() {
    # There is a mandatory 90 second recovery when starting the NFSv4
    # server, so put these later in the list to avoid a pause when doing
    # switch_root

    client_test "NFSv4 root=dhcp DHCP proto:IP:path" 52:54:00:12:34:82 \
        "root=dhcp" 192.168.50.3 -wsize=4096

    client_test "NFSv4 root=dhcp DHCP proto:IP:path:options" 52:54:00:12:34:83 \
        "root=dhcp" 192.168.50.3 wsize=4096

    client_test "NFSv4 root=nfs4:..." 52:54:00:12:34:84 \
        "root=nfs4:192.168.50.1:/client" 192.168.50.1 -wsize=4096

    client_test "NFSv4 root=dhcp DHCP proto:IP:path,options" 52:54:00:12:34:87 \
        "root=dhcp" 192.168.50.3 wsize=4096

    client_test "NFSv4 Overlayfs root=nfs4:..." 52:54:00:12:34:84 \
        "root=nfs4:192.168.50.1:/client rd.live.overlay.overlayfs=1 " 192.168.50.1 -wsize=4096

    client_test "NFSv4 Live Overlayfs root=nfs4:..." 52:54:00:12:34:84 \
        "root=nfs4:192.168.50.1:/client rd.live.image rd.live.overlay.overlayfs=1" 192.168.50.1 -wsize=4096

    return 0
}

test_run() {
    if [[ -s server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

    if ! run_server; then
        echo "Failed to start server" 1>&2
        return 1
    fi

    test_nfsv3 \
        && test_nfsv4

    ret=$?

    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

    return $ret
}

test_setup() {
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a "url-lib nfs" \
        -I "ip grep setsid" \
        -f "$TESTDIR"/initramfs.root || return 1

    mkdir -p "$TESTDIR"/server/overlay

    # Create what will eventually be the server root filesystem onto an overlay
    "$DRACUT" -N --keep --tmpdir "$TESTDIR"/server/overlay \
        --add-confdir test-root \
        -a "bash $USE_NETWORK nfs" \
        --add-drivers "nfsd sunrpc lockd" \
        -I "exportfs rpc.nfsd rpc.mountd dhcpd" \
        --install-optional "/etc/netconfig /etc/nsswitch.conf /etc/rpc /etc/protocols /etc/services /usr/etc/nsswitch.conf /usr/etc/rpc /usr/etc/protocols /usr/etc/services rpc.idmapd /etc/idmapd.conf" \
        -i "./dhcpd.conf" "/etc/dhcpd.conf" \
        -f "$TESTDIR"/initramfs.root

    mkdir -p "$TESTDIR"/server/overlay/source && mv "$TESTDIR"/server/overlay/dracut.*/initramfs/* "$TESTDIR"/server/overlay/source && rm -rf "$TESTDIR"/server/overlay/dracut.*

    export initdir=$TESTDIR/server/overlay/source
    mkdir -p "$initdir"/var/lib/{dhcpd,rpcbind} "$initdir"/var/lib/nfs/{v4recovery,rpc_pipefs}
    chmod 777 "$initdir"/var/lib/{dhcpd,rpcbind}
    cp ./server-init.sh "$initdir"/sbin/init
    cp ./exports "$initdir"/etc/exports
    cp ./dhcpd.conf "$initdir"/etc/dhcpd.conf

    # Make client root inside server root
    # shellcheck disable=SC2031
    export initdir=$TESTDIR/server/overlay/source/nfs/client
    mkdir -p "$initdir" && mv "$TESTDIR"/dracut.*/initramfs/* "$initdir" && rm -rf "$TESTDIR"/dracut.*
    echo "TEST FETCH FILE" > "$initdir"/root/fetchfile
    cp ./client-init.sh "$initdir"/sbin/init

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -i "$TESTDIR"/server/overlay / \
        --add-confdir test-makeroot \
        -a "bash rootfs-block kernel-modules qemu" \
        --add-drivers "ext4" \
        -I "mkfs.ext4" \
        -i ./create-root.sh /lib/dracut/hooks/initqueue/01-create-root.sh \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot
    rm -rf -- "$TESTDIR"/server

    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created

    # Make client's dracut image
    test_dracut \
        --no-hostonly --no-hostonly-cmdline \
        --include ./client.link /etc/systemd/network/01-client.link \
        -a "watchdog dmsquash-live ${USE_NETWORK}"

    # Make server's dracut image
    "$DRACUT" -i "$TESTDIR"/overlay / \
        -a "bash $USE_NETWORK ${SERVER_DEBUG:+debug}" \
        --include ./server.link /etc/systemd/network/01-server.link \
        --include ./wait-if-server.sh /lib/dracut/hooks/pre-mount/99-wait-if-server.sh \
        --add-drivers "ext4" \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.server
}

test_cleanup() {
    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

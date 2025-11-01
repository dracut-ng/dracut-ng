#!/usr/bin/env bash
set -eu

[ -z "${USE_NETWORK-}" ] && USE_NETWORK="network"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem over multiple iSCSI with $USE_NETWORK"

#DEBUGFAIL="rd.shell rd.break rd.debug loglevel=7 "
#SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="tcp:127.0.0.1:9999"

run_server() {
    # Start server first
    echo "iSCSI TEST SETUP: Starting DHCP/iSCSI server"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img serverroot 0 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/singleroot.img singleroot
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid0-1.img raid0-1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid0-2.img raid0-2

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -net nic,macaddr=52:54:00:12:34:56,model=virtio \
        -net nic,macaddr=52:54:00:12:34:57,model=virtio \
        -net socket,listen=127.0.0.1:12331 \
        -append "panic=1 oops=panic softlockup_panic=1 systemd.crash_reboot root=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_serverroot rootfstype=ext4 rw console=ttyS0,115200n81 ${SERVER_DEBUG-}" \
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

run_client() {
    local test_name=$1
    shift
    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker

    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net nic,macaddr=52:54:00:12:34:00,model=virtio \
        -net nic,macaddr=52:54:00:12:34:01,model=virtio \
        -net socket,connect=127.0.0.1:12331 \
        -append "$TEST_KERNEL_CMDLINE rw rd.auto $*" \
        -initrd "$TESTDIR"/initramfs.testing
    if ! test_marker_check iscsi-OK; then
        echo "CLIENT TEST END: $test_name [FAILED - BAD EXIT]"
        return 1
    fi

    echo "CLIENT TEST END: $test_name [OK]"
    return 0
}

do_test_run() {
    initiator=$(iscsi-iname)
    run_client "netroot=iscsi target1 target2" \
        "root=LABEL=sysroot" \
        "ip=192.168.50.101:::255.255.255.0::lan0:off" \
        "ip=192.168.51.101:::255.255.255.0::lan1:off" \
        "netroot=iscsi:192.168.51.1::::iqn.2009-06.dracut:target1" \
        "netroot=iscsi:192.168.50.1::::iqn.2009-06.dracut:target2" \
        "rd.iscsi.initiator=$initiator"

    run_client "netroot=iscsi target1 target2 rd.iscsi.waitnet=0" \
        "root=LABEL=sysroot" \
        "ip=192.168.50.101:::255.255.255.0::lan0:off" \
        "ip=192.168.51.101:::255.255.255.0::lan1:off" \
        "netroot=iscsi:192.168.51.1::::iqn.2009-06.dracut:target1" \
        "netroot=iscsi:192.168.50.1::::iqn.2009-06.dracut:target2" \
        "rd.iscsi.firmware" \
        "rd.iscsi.initiator=$initiator" \
        "rd.iscsi.waitnet=0"

    run_client "netroot=iscsi target1 target2 rd.iscsi.waitnet=0 rd.iscsi.testroute=0" \
        "root=LABEL=sysroot" \
        "ip=192.168.50.101:::255.255.255.0::lan0:off" \
        "ip=192.168.51.101:::255.255.255.0::lan1:off" \
        "netroot=iscsi:192.168.51.1::::iqn.2009-06.dracut:target1" \
        "netroot=iscsi:192.168.50.1::::iqn.2009-06.dracut:target2" \
        "rd.iscsi.firmware" \
        "rd.iscsi.initiator=$initiator" \
        "rd.iscsi.waitnet=0 rd.iscsi.testroute=0"

    run_client "netroot=iscsi target1 target2 rd.iscsi.waitnet=0 rd.iscsi.testroute=0 default GW" \
        "root=LABEL=sysroot" \
        "ip=192.168.50.101::192.168.50.1:255.255.255.0::lan0:off" \
        "ip=192.168.51.101::192.168.51.1:255.255.255.0::lan1:off" \
        "netroot=iscsi:192.168.51.1::::iqn.2009-06.dracut:target1" \
        "netroot=iscsi:192.168.50.1::::iqn.2009-06.dracut:target2" \
        "rd.iscsi.firmware" \
        "rd.iscsi.initiator=$initiator" \
        "rd.iscsi.waitnet=0 rd.iscsi.testroute=0"

    echo "All tests passed [OK]"
    return 0
}

test_run() {
    if ! run_server; then
        echo "Failed to start server" 1>&2
        return 1
    fi
    do_test_run
    ret=$?
    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
    return $ret
}

test_check() {
    if ! command -v tgtd &> /dev/null || ! command -v tgtadm &> /dev/null; then
        echo "Need tgtd and tgtadm from scsi-target-utils"
        return 1
    fi
}

test_setup() {
    # Create what will eventually be our root filesystem onto an overlay
    rm -rf -- "$TESTDIR"/overlay
    call_dracut --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -I "ip grep setsid" \
        --no-hostonly \
        -f "$TESTDIR"/initramfs.root
    mkdir -p "$TESTDIR"/overlay/source
    mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source
    rm -rf "$TESTDIR"/dracut.*
    mkdir -p -- "$TESTDIR"/overlay/source/var/lib/nfs/rpc_pipefs
    inst_init ./client-init.sh "$TESTDIR"/overlay/source

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    call_dracut -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -a "crypt lvm mdraid" \
        -I "setsid blockdev" \
        -i ./create-client-root.sh /lib/dracut/hooks/initqueue/01-create-client-root.sh \
        -f "$TESTDIR"/initramfs.makeroot
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/singleroot.img singleroot 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid0-1.img raid0-1 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/raid0-2.img raid0-2 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/fakeroot rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created
    rm -- "$TESTDIR"/marker.img

    rm -rf -- "$TESTDIR"/overlay
    call_dracut --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -a "$USE_NETWORK iscsi" \
        -d "iscsi_tcp crc32c ipv6 af_packet" \
        -I "ip grep sleep setsid chmod modprobe pidof tgtd tgtadm" \
        --install-optional "/etc/netconfig dhcpd /etc/group /etc/nsswitch.conf /etc/rpc /etc/protocols /etc/services /usr/etc/nsswitch.conf /usr/etc/rpc /usr/etc/protocols /usr/etc/services" \
        -i /tmp/config /etc/nbd-server/config \
        -i "./dhcpd.conf" "/etc/dhcpd.conf" \
        -f "$TESTDIR"/initramfs.root
    mkdir -p "$TESTDIR"/overlay/source
    mv "$TESTDIR"/dracut.*/initramfs/* "$TESTDIR"/overlay/source
    rm -rf "$TESTDIR"/dracut.*

    mkdir -p -- "$TESTDIR"/overlay/source/var/lib/dhcpd "$TESTDIR"/overlay/source/etc/iscsi
    inst_init ./server-init.sh "$TESTDIR"/overlay/source

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    call_dracut -i "$TESTDIR"/overlay / \
        --add-confdir test-makeroot \
        -i ./create-server-root.sh /lib/dracut/hooks/initqueue/01-create-server-root.sh \
        -f "$TESTDIR"/initramfs.makeroot
    rm -rf -- "$TESTDIR"/overlay

    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker 1
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img root 1

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext4 quiet console=ttyS0,115200n81" \
        -initrd "$TESTDIR"/initramfs.makeroot
    test_marker_check dracut-root-block-created
    rm -- "$TESTDIR"/marker.img

    # Make client's dracut image
    test_dracut \
        --no-hostonly \
        --add "watchdog qemu-net $USE_NETWORK" \
        -i ./client-persistent-lan0.link /etc/systemd/network/01-persistent-lan0.link \
        -i ./client-persistent-lan1.link /etc/systemd/network/01-persistent-lan1.link

    # Make server's dracut image
    call_dracut \
        --add-confdir test \
        -a "qemu-net $USE_NETWORK ${SERVER_DEBUG:+debug}" \
        -i "./server.link" "/etc/systemd/network/01-server.link" \
        -i "./wait-if-server.sh" "/lib/dracut/hooks/pre-mount/99-wait-if-server.sh" \
        -N \
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

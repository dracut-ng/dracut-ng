#!/usr/bin/env bash
set -e

[ -z "${USE_NETWORK-}" ] && USE_NETWORK="network"

# shellcheck disable=SC2034
TEST_DESCRIPTION="root filesystem on NFS with multiple nics with $USE_NETWORK"

# Uncomment this to debug failures
#DEBUGFAIL="loglevel=7 rd.shell rd.break"
#SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="tcp:127.0.0.1:9999"

# skip the test if ifcfg dracut module can not be installed
test_check() {
    if ! type -p dhclient &> /dev/null; then
        echo "Test needs dhclient for server networking... Skipping"
        return 1
    fi

    command -v exportfs &> /dev/null

    # TODO: remove this check and make this test work on other distributions as well not just fedora
    [ -f /usr/lib/os-release ] && . /usr/lib/os-release && [ "$ID" = "fedora" ]
}

run_server() {
    # Start server first
    echo "MULTINIC TEST SETUP: Starting DHCP/NFS server"

    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/server.img root

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net socket,listen=127.0.0.1:12350 \
        -net nic,macaddr=52:54:00:42:00:01,model=virtio \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -append "panic=1 oops=panic softlockup_panic=1 systemd.crash_reboot root=LABEL=dracut rootfstype=ext4 rw console=ttyS0,115200n81 $SERVER_DEBUG" \
        -initrd "$TESTDIR"/initramfs.server \
        -pidfile "$TESTDIR"/server.pid -daemonize

    chmod 644 -- "$TESTDIR"/server.pid

    if ! [[ $SERIAL ]]; then
        wait_for_server_startup
    else
        echo Sleeping 10 seconds to give the server a head start
        sleep 10
    fi
}

client_test() {
    local test_name="$1"
    local mac1="$2"
    local mac2="$3"
    local mac3="$4"
    local cmdline="$5"
    local check="$6"

    echo "CLIENT TEST START: $test_name"

    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    cmdline="$cmdline rd.net.timeout.dhcp=30"

    # Invoke KVM and/or QEMU to actually create the target filesystem.
    test_marker_reset
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net socket,connect=127.0.0.1:12350 \
        -net nic,macaddr=52:54:00:12:34:"$mac1",model=virtio \
        -net nic,macaddr=52:54:00:12:34:"$mac2",model=virtio \
        -net nic,macaddr=52:54:00:12:34:"$mac3",model=virtio \
        -netdev hubport,id=n1,hubid=1 \
        -netdev hubport,id=n2,hubid=2 \
        -device virtio-net-pci,netdev=n1,mac=52:54:00:12:34:98 \
        -device virtio-net-pci,netdev=n2,mac=52:54:00:12:34:99 \
        -append "$TEST_KERNEL_CMDLINE $cmdline ro init=/sbin/init systemd.log_target=console" \
        -initrd "$TESTDIR"/initramfs.testing

    {
        read -r OK
        read -r IFACES
    } < "$TESTDIR"/marker.img

    if [[ $OK != "OK" ]]; then
        echo "CLIENT TEST END: $test_name [FAILED - BAD EXIT]"
        return 1
    fi

    for i in $check; do
        if [[ " $IFACES " != *\ $i\ * ]]; then
            echo "$i not in '$IFACES'"
            echo "CLIENT TEST END: $test_name [FAILED - BAD IF]"
            return 1
        fi
    done

    for i in $IFACES; do
        if [[ " $check " != *\ $i\ * ]]; then
            echo "$i in '$IFACES', but should not be"
            echo "CLIENT TEST END: $test_name [FAILED - BAD IF]"
            return 1
        fi
    done

    echo "CLIENT TEST END: $test_name [OK]"
    return 0
}

test_run() {
    if ! run_server; then
        echo "Failed to start server" 1>&2
        return 1
    fi
    test_client
    ret=$?
    kill_server
    return $ret
}

test_client() {
    # Mac Numbering Scheme
    # ...:00-02 receive IP addresses all others don't
    # ...:02 receives a dhcp root-path

    # PXE Style BOOTIF=
    client_test "MULTINIC root=nfs BOOTIF=" \
        00 01 02 \
        "root=nfs:192.168.50.1:/nfs/client BOOTIF=52-54-00-12-34-00" \
        "lan0"

    client_test "MULTINIC root=nfs BOOTIF= ip=lan2:dhcp" \
        00 01 02 \
        "root=nfs:192.168.50.1:/nfs/client BOOTIF=52-54-00-12-34-00 ip=lan1:dhcp" \
        "lan0 lan1"

    # PXE Style BOOTIF= with dhcp root-path
    client_test "MULTINIC root=dhcp BOOTIF=" \
        00 01 02 \
        "root=dhcp BOOTIF=52-54-00-12-34-02" \
        "lan2"

    # Multinic case, where only one nic works
    client_test "MULTINIC root=nfs ip=dhcp" \
        FF 00 FE \
        "root=nfs:192.168.50.1:/nfs/client ip=dhcp" \
        "lan0"

    # Require two interfaces
    client_test "MULTINIC root=nfs ip=lan1:dhcp ip=lan2:dhcp bootdev=lan1" \
        00 01 02 \
        "root=nfs:192.168.50.1:/nfs/client ip=lan1:dhcp ip=lan2:dhcp bootdev=lan1" \
        "lan1 lan2"

    # Require three interfaces with dhcp root-path
    client_test "MULTINIC root=dhcp ip=lan0:dhcp ip=lan1:dhcp ip=lan2:dhcp bootdev=lan2" \
        00 01 02 \
        "root=dhcp ip=lan0:dhcp ip=lan1:dhcp ip=lan2:dhcp bootdev=lan2" \
        "lan0 lan1 lan2"

    client_test "MULTINIC bonding" \
        00 01 02 \
        "root=nfs:192.168.50.1:/nfs/client ip=bond0:dhcp  bond=bond0:lan0,lan1,lan2:mode=balance-rr" \
        "bond0"

    # bridge, where only one interface is actually connected
    client_test "MULTINIC bridging" \
        00 01 02 \
        "root=nfs:192.168.50.1:/nfs/client ip=bridge0:dhcp::52:54:00:12:34:00 bridge=bridge0:lan0,lan98,lan99" \
        "bridge0"
    return 0
}

test_setup() {
    # shellcheck disable=SC2153
    export kernel=$KVERSION
    export srcmods="/lib/modules/$kernel/"
    rm -rf -- "$TESTDIR"/overlay
    (
        mkdir -p "$TESTDIR"/overlay/source
        # shellcheck disable=SC2030
        export initdir=$TESTDIR/overlay/source
        # shellcheck disable=SC1090
        . "$PKGLIBDIR"/dracut-init.sh

        (
            cd "$initdir" || exit
            mkdir -p dev sys proc run etc var/run tmp var/lib/{dhcpd,rpcbind}
            mkdir -p var/lib/nfs/{v4recovery,rpc_pipefs}
            chmod 777 var/lib/rpcbind var/lib/nfs
        )

        inst_multiple sh ls shutdown poweroff cat ps ln ip \
            dmesg mkdir cp exportfs \
            modprobe rpc.nfsd rpc.mountd \
            sleep mount chmod rm
        for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
            if [ -f "${_terminfodir}"/l/linux ]; then
                inst_multiple -o "${_terminfodir}"/l/linux
                break
            fi
        done
        type -P portmap > /dev/null && inst_multiple portmap
        type -P rpcbind > /dev/null && inst_multiple rpcbind
        [ -f /etc/netconfig ] && inst_multiple /etc/netconfig
        type -P dhcpd > /dev/null && inst_multiple dhcpd
        instmods nfsd sunrpc ipv6 lockd af_packet
        inst ./server-init.sh /sbin/init
        inst_simple /etc/os-release
        inst ./exports /etc/exports
        inst ./dhcpd.conf /etc/dhcpd.conf
        inst_multiple -o {,/usr}/etc/nsswitch.conf {,/usr}/etc/rpc \
            {,/usr}/etc/protocols {,/usr}/etc/services
        inst_multiple -o rpc.idmapd /etc/idmapd.conf

        inst_libdir_file 'libnfsidmap_nsswitch.so*'
        inst_libdir_file 'libnfsidmap/*.so*'
        inst_libdir_file 'libnfsidmap*.so*'

        _nsslibs=$(
            cat "${dracutsysrootdir-}"/{,usr/}etc/nsswitch.conf 2> /dev/null \
                | sed -e '/^#/d' -e 's/^.*://' -e 's/\[NOTFOUND=return\]//' \
                | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' '|'
        )
        _nsslibs=${_nsslibs#|}
        _nsslibs=${_nsslibs%|}
        inst_libdir_file -n "$_nsslibs" 'libnss_*.so*'

        inst /etc/passwd /etc/passwd
        inst /etc/group /etc/group

        cp -a /etc/ld.so.conf* "$initdir"/etc
        ldconfig -r "$initdir"
        dracut_kernel_post
    )

    # Make client root inside server root
    (
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        export initdir=$TESTDIR/overlay/source/nfs/client
        # shellcheck disable=SC1090
        . "$PKGLIBDIR"/dracut-init.sh

        (
            cd "$initdir" || exit
            mkdir -p dev sys proc etc run root usr var/lib/nfs/rpc_pipefs
        )

        inst_multiple sh shutdown poweroff cat ps ln ip dd \
            mount dmesg mkdir cp grep setsid ls cat sync
        for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
            if [ -f "${_terminfodir}"/l/linux ]; then
                inst_multiple -o "${_terminfodir}"/l/linux
                break
            fi
        done

        inst ./client-init.sh /sbin/init
        inst_simple /etc/os-release
        inst_multiple -o {,/usr}/etc/nsswitch.conf
        inst /etc/passwd /etc/passwd
        inst /etc/group /etc/group

        inst_libdir_file 'libnfsidmap_nsswitch.so*'
        inst_libdir_file 'libnfsidmap/*.so*'
        inst_libdir_file 'libnfsidmap*.so*'

        _nsslibs=$(
            cat "${dracutsysrootdir-}"/{,usr/}etc/nsswitch.conf 2> /dev/null \
                | sed -e '/^#/d' -e 's/^.*://' -e 's/\[NOTFOUND=return\]//' \
                | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' '|'
        )
        _nsslibs=${_nsslibs#|}
        _nsslibs=${_nsslibs%|}
        inst_libdir_file -n "$_nsslibs" 'libnss_*.so*'

        cp -a /etc/ld.so.conf* "$initdir"/etc
        ldconfig -r "$initdir"
    )

    # second, install the files needed to make the root filesystem
    (
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        export initdir=$TESTDIR/overlay
        # shellcheck disable=SC1090
        . "$PKGLIBDIR"/dracut-init.sh
        inst_multiple mkfs.ext4 poweroff cp umount sync dd
        inst_hook initqueue 01 ./create-root.sh
        inst_hook initqueue/finished 01 ./finished-false.sh
    )

    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    "$DRACUT" -i "$TESTDIR"/overlay / \
        -m "bash rootfs-block kernel-modules qemu" \
        -d "piix ide-gd_mod ata_piix ext4 sd_mod" \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION"
    rm -rf -- "$TESTDIR"/overlay

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

    # Make an overlay with needed tools for the test harness
    (
        # shellcheck disable=SC2031
        # shellcheck disable=SC2030
        export initdir="$TESTDIR"/overlay
        mkdir -p "$TESTDIR"/overlay
        # shellcheck disable=SC1090
        . "$PKGLIBDIR"/dracut-init.sh
        inst_multiple poweroff shutdown
        inst_hook shutdown-emergency 000 ./hard-off.sh
        inst_hook emergency 000 ./hard-off.sh
        inst_simple ./client-persistent-lan0.link /etc/systemd/network/01-persistent-lan0.link
        inst_simple ./client-persistent-lan1.link /etc/systemd/network/01-persistent-lan1.link
        inst_simple ./client-persistent-lan2.link /etc/systemd/network/01-persistent-lan2.link
        inst_simple ./client-persistent-lan98.link /etc/systemd/network/01-persistent-lan98.link
        inst_simple ./client-persistent-lan99.link /etc/systemd/network/01-persistent-lan99.link
        inst_simple ./client-persistent-lan254.link /etc/systemd/network/01-persistent-lan254.link
        inst_simple ./client-persistent-lan255.link /etc/systemd/network/01-persistent-lan255.link

        inst_binary awk
    )
    # Make client's dracut image
    test_dracut \
        --no-hostonly --no-hostonly-cmdline \
        -a "${USE_NETWORK}"

    (
        # shellcheck disable=SC2031
        export initdir="$TESTDIR"/overlay
        # shellcheck disable=SC1090
        . "$PKGLIBDIR"/dracut-init.sh
        rm "$initdir"/etc/systemd/network/01-persistent-lan*.link
        inst_simple ./server.link /etc/systemd/network/01-server.link
        inst_hook pre-mount 99 ./wait-if-server.sh
    )
    # Make server's dracut image
    "$DRACUT" -i "$TESTDIR"/overlay / \
        -m "bash rootfs-block kernel-modules watchdog qemu network-legacy ${SERVER_DEBUG:+debug}" \
        -d "af_packet piix ide-gd_mod ata_piix ext4 sd_mod nfsv2 nfsv3 nfsv4 nfs_acl nfs_layout_nfsv41_files nfsd i6300esb virtio_net" \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.server "$KVERSION"

}

kill_server() {
    if [[ -s "$TESTDIR"/server.pid ]]; then
        kill -TERM -- "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

test_cleanup() {
    kill_server
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

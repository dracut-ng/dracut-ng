#!/usr/bin/env bash
set -e

# shellcheck disable=SC2034
TEST_DESCRIPTION="boot into storage-target-mode"

test_check() {
    if ! [ -f /usr/lib/systemd/systemd-storagetm ]; then
        echo "Test needs systemd-storagetm for server... Skipping"
        return 1
    fi

    if ! type -p nvme &> /dev/null; then
        echo "Test needs nvme cli... Skipping"
        return 1
    fi

    if ! modinfo -k "$KVERSION" nvmet_tcp &> /dev/null; then
        echo "Kernel module nvmet_tcp does not exist"
        return 1
    fi

    if ! modinfo -k "$KVERSION" nvme_tcp &> /dev/null; then
        echo "Kernel module nvme_tcp does not exist"
        return 1
    fi

    return 0
}

test_run() {
    declare -a disk_args=()
    # shellcheck disable=SC2034  # disk_index used in qemu_add_drive
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/unencrypted.img unencrypted 1

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -serial "file:$TESTDIR/server.log" \
        -net nic,macaddr=52:54:00:12:34:00,model=virtio \
        -net user,hostfwd=tcp::12340-:57838 \
        -append "ro console=ttyS0,115200n81 rd.systemd.unit=storage-target-mode.target ip=link-local systemd.machine-id=a96049038d3041f7a9c666a56f4805ba" \
        -initrd "$TESTDIR"/initramfs.testing \
        -pidfile "$TESTDIR"/server.pid -daemonize
    chmod 644 "$TESTDIR"/server.pid

    wait_for_storagetm_listen

    echo "Attempting to connect to NVMe over TCP"
    nvme discover -t tcp -a 127.0.0.1 -s 12340

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        echo "CLIENT TEST END: $test_name [FAILED - UNABLE TO CONNECT TO NVME-OF TARGET]"
        return 1
    fi

    echo "CLIENT TEST END: $test_name [OK]"

    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

test_setup() {
    test_dracut \
        --no-hostonly --no-hostonly-cmdline \
        --add "systemd-storagetm"
}

# Wait for systemd-storagetm to run
# It should print "Listening on ipv4" in the server.log in that case.
wait_for_storagetm_listen() {
    local lines printed_lines=0 server_pid
    server_pid=$(cat "$TESTDIR"/server.pid)

    echo "Waiting for systemd-storagetm to startup"
    while ! grep -q "Listening on ipv4" "$TESTDIR"/server.log; do
        if [ "$V" -ge 1 ]; then
            lines=$(wc -l "$TESTDIR"/server.log | cut -f 1 -d ' ')
            if [ "$lines" -gt "$printed_lines" ]; then
                tail -n "+$((printed_lines + 1))" "$TESTDIR"/server.log
                printed_lines=$lines
            fi
        fi
        if ! test -f "/proc/$server_pid/status"; then
            echo "Error: Server QEMU process $server_pid is gone. Please check $TESTDIR/server.log for failures." >&2
            return 1
        fi
        sleep 1
    done
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

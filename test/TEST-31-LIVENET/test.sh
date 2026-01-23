#!/usr/bin/env bash
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="live root provided over network"

# Uncomment these to debug failures
#DEBUGFAIL="rd.shell rd.debug rd.live.debug loglevel=7"

test_check() {
    if ! type -p mksquashfs &> /dev/null; then
        echo "Test needs mksquashfs... Skipping"
        return 1
    fi

    if ! type -p python3 &> /dev/null; then
        echo "Test needs python3 as HTTP server... Skipping"
        return 1
    fi
}

start_webserver() {
    local pid port

    echo "Starting HTTP server..." >&2
    python3 -u -m http.server -d "$TESTDIR" 0 > "$TESTDIR/webserver.log" 2>&1 &
    pid=$!
    echo "$pid" > "$TESTDIR/webserver.pid"

    while ! grep -q 'Serving HTTP on' "$TESTDIR/webserver.log"; do
        echo "sleeping..." >&2
        sleep 0.05
    done

    port=$(sed -n 's/.*port \([0-9]\+\).*/\1/p' "$TESTDIR/webserver.log")
    echo "HTTP server running on port $port (pid $pid)" >&2
    echo "$port"
}

client_run() {
    local test_name="$1"
    local append="$2"

    client_test_start "$test_name"
    "$testdir"/run-qemu \
        -device "virtio-net-pci,netdev=lan0" \
        -netdev "user,id=lan0,net=10.0.2.0/24,dhcpstart=10.0.2.15" \
        -append "$append $TEST_KERNEL_CMDLINE" \
        -initrd "$TESTDIR/initramfs.testing"
    check_qemu_log
    client_test_end
}

test_run() {
    port=$(start_webserver)

    client_run "root=live:http://server/root.squashfs" "root=live:http://10.0.2.2:$port/root.squashfs"
    client_run "root=http://server/root.squashfs" "root=http://10.0.2.2:$port/root.squashfs"
}

test_setup() {
    # create root filesystem
    call_dracut --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root

    mksquashfs "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR/root.squashfs" -quiet

    test_dracut -a "livenet" --no-hostonly
}

test_cleanup() {
    if [[ -s "$TESTDIR/webserver.pid" ]]; then
        pid=$(cat "$TESTDIR/webserver.pid")
        echo "Stopping HTTP server (pid $pid)..." >&2
        kill "$pid"
        rm "$TESTDIR/webserver.pid"
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

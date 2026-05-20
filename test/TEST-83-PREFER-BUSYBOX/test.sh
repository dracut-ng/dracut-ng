#!/usr/bin/env bash
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="prefer_busybox=yes makes busybox provide coreutils applets"

test_check() {
    if ! command -v busybox &> /dev/null; then
        echo "Busybox binary is required... Skipping"
        return 1
    fi
}

test_setup() {
    mkdir -p "$TESTDIR"/dracut.conf.d/
    echo -n "prefer_busybox=yes" > "$TESTDIR"/dracut.conf.d/test.conf
    test_dracut --no-hostonly --modules "bash base busybox" || return 1
}

test_run() {
    local _output _applet _ret=0
    declare -A _bb_applets

    _output=$(lsinitrd "$TESTDIR"/initramfs.testing) || return 1

    while read -r _applet; do
        _bb_applets[$_applet]=1
    done < <(busybox --list)

    # Mirror of 80base's _progs list
    local _progs=(
        cp
        dmesg
        flock
        ln
        ls
        mkdir
        mkfifo
        mknod
        modprobe
        mount
        mv
        readlink
        rm
        rmmod
        sed
        setsid
        sleep
        tr
        umount
    )

    for _applet in "${_progs[@]}"; do
        [[ ${_bb_applets[$_applet]:-} ]] || continue
        if ! grep -qE "/${_applet} -> .*busybox" <<< "$_output"; then
            echo "FAIL: /usr/bin/${_applet} should be a symlink to busybox" >&2
            _ret=1
        fi
    done

    return $_ret
}

. "$testdir"/test-functions

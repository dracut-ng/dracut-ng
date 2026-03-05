#!/bin/sh
set -eu

# required binaries: dnsmasq ip mount nbd-server pidof poweroff sleep

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# shellcheck disable=SC2317,SC2329  # called via EXIT trap
_poweroff() {
    local exit_code="$?"

    set +x
    [ "$exit_code" -eq 0 ] || echo "Error: $0 failed with exit code $exit_code."
    echo "Powering down."

    poweroff -f
}

trap _poweroff EXIT

exec < /dev/console > /dev/console 2>&1
set -x
export TERM=linux
export PS1='nbdtest-server:\w\$ '
echo "made it to the NBD server rootfs!"
echo server > /proc/sys/kernel/hostname

wait_for_if_link() {
    local cnt=0
    local li
    while [ $cnt -lt 600 ]; do
        li=$(ip -o link show dev "$1" 2> /dev/null)
        [ -n "$li" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

wait_for_if_up() {
    local cnt=0
    local li
    while [ $cnt -lt 200 ]; do
        li=$(ip -o link show up dev "$1")
        [ -n "$li" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

wait_for_route_ok() {
    local cnt=0
    while [ $cnt -lt 200 ]; do
        li=$(ip route show)
        [ -n "$li" ] && [ -z "${li##*"$1"*}" ] && return 0
        sleep 0.1
        cnt=$((cnt + 1))
    done
    return 1
}

linkup() {
    wait_for_if_link "$1" 2> /dev/null && ip link set "$1" up 2> /dev/null && wait_for_if_up "$1" 2> /dev/null
}

wait_for_if_link enx525400123456
ip addr add 192.168.50.1/24 dev enx525400123456
linkup enx525400123456

nbd-server
dnsmasq
echo "Serving NBD disks"
while pidof nbd-server && pidof dnsmasq; do
    echo > /dev/watchdog
    sleep 1
done
mount -n -o remount,ro /

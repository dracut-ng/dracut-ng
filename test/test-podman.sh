#!/bin/sh

set -ex

TESTS=$1
CONTAINER=$2

[ -z "$CONTAINER" ] && CONTAINER='ghcr.io/dracut-ng/fedora'

podman run --rm -it --device=/dev/kvm -v "$PWD"/:/z "$CONTAINER" /z/test/test-github.sh id "$TESTS"

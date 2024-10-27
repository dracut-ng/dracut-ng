#!/bin/bash

set -e

CONTAINER=$1
TESTS=$2

[ -z "$CONTAINER" ] && CONTAINER='fedora'

if command -v podman &> /dev/null; then
    podman run --rm -it --device=/dev/kvm -e V=0 -v "$PWD"/:/z "ghcr.io/dracut-ng/$CONTAINER" /z/test/test-github.sh id "$TESTS"
else
    docker run --rm -it --device=/dev/kvm -e V=0 -v "$PWD"/:/z "ghcr.io/dracut-ng/$CONTAINER" /z/test/test-github.sh id "$TESTS"
fi

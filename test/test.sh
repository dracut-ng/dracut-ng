#!/bin/bash

# convenience script for development to run integration tests
# runs test-container.sh in a container

set -e

export CONTAINER="${CONTAINER:=$1}"
export CONTAINER="${CONTAINER:=fedora}"
export TESTS="${TESTS:=$2}"
export TEST_RUN_ID="${TEST_RUN_ID:=id}"

# if registry is not specified, add our registry
if [[ $CONTAINER != *"/"* ]]; then
    CONTAINER="ghcr.io/dracut-ng/$CONTAINER"
fi

# if label is not specified, add latest label
if [[ $CONTAINER != *":"* ]]; then
    CONTAINER="$CONTAINER:latest"
fi

# add architecture tag, see commit d8ff139
ARCH="${ARCH-$(uname -m)}"
case "$ARCH" in
    aarch64 | arm64)
        CONTAINER="$CONTAINER-arm"
        ;;
    amd64 | i?86 | x86_64)
        CONTAINER="$CONTAINER-amd"
        ;;
esac

echo "Running in a container from $CONTAINER"

if command -v podman &> /dev/null; then
    PODMAN=podman
else
    PODMAN=docker
fi

# Compute wildcards for TESTS variable (e.g. '1*')
# shellcheck disable=SC1001
[ -n "$TESTS" ] && TESTS=$(
    cd test
    for T in ${TESTS}; do find . -depth -type d -name "TEST-*${T}*" -exec echo {} \; | cut -d\- -f2 | tr '\n' ' '; done
)

# clear previous test run
TARGETS='clean all install check' "$PODMAN" run --rm -it \
    --device=/dev/kvm --privileged \
    -e V -e TESTS -e TEST_RUN_ID -e TARGETS -e MAKEFLAGS \
    -v "$PWD"/:/z \
    "$CONTAINER" \
    /z/test/test-container.sh

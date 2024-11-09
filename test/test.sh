#!/bin/bash

# convenience script for development to run integration tests
# runs test-github.sh in a container

set -e

export CONTAINER="${CONTAINER:=$1}"
export CONTAINER="${CONTAINER:=fedora}"
export TESTS="${TESTS:=$2}"
export TEST_RUN_ID="${TEST_RUN_ID:=id}"

if command -v podman &> /dev/null; then
    PODMAN=podman
else
    PODMAN=docker
fi

# clear previous test run
TARGETS='clean all install check' "$PODMAN" run --rm -it \
    --device=/dev/kvm \
    -e V -e TESTS -e TEST_RUN_ID -e TARGETS \
    -v "$PWD"/:/z \
    "ghcr.io/dracut-ng/$CONTAINER" \
    /z/test/test-github.sh

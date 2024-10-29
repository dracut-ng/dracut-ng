#!/bin/bash

# script for integration testing invoked by GitHub Actions
# wraps configure && make
# assumes that it runs inside a CI container

set -e
if [ "$V" = "2" ]; then set -x; fi

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

# disable documentation for extended tests
if [ "$2" != "10" ]; then
    CONFIGURE_ARG+=" --disable-documentation"
fi

# if is cargo installed, let's build and test dracut-cpio
if command -v cargo > /dev/null; then
    CONFIGURE_ARG+=" --enable-dracut-cpio"
fi

# shellcheck disable=SC2086
./configure $CONFIGURE_ARG

# treat warnings as error
# shellcheck disable=SC2086
CFLAGS="-Wextra -Werror" make TEST_RUN_ID="${TEST_RUN_ID:=$1}" TESTS="${TESTS:=$2}" V="${V:=1}" ${TARGETS:=all check}

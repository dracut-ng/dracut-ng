#!/bin/bash

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

V="${V:=1}"

# treat warnings as error
CFLAGS="-Wextra -Werror" make -j "$(getconf _NPROCESSORS_ONLN)" all

cd test && time make TEST_RUN_ID="$1" TESTS="$2" -k V="$V" check

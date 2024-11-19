#!/bin/bash

# script for integration testing invoked by GitHub Actions
# wraps configure && make
# assumes that it runs inside a CI container

set -e
if [ "$V" = "2" ]; then set -x; fi

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

# disable building documentation by default
[ -z "$enable_documentation" ] && export enable_documentation=no

# shellcheck disable=SC2086
./configure $CONFIGURE_ARG

TESTS="${TESTS:=$2}"

# Compute wildcards for TESTS variable (e.g. '1*')
# shellcheck disable=SC1001
[ -n "$TESTS" ] && TESTS=$(
    cd test
    for T in ${TESTS}; do find . -depth -type d -name "TEST-*${T}*" -exec echo {} \; | cut -d\- -f2 | tr '\n' ' '; done
)

# treat warnings as error
# shellcheck disable=SC2086
CFLAGS="-Wextra -Werror" make TEST_RUN_ID="${TEST_RUN_ID:=$1}" TESTS="${TESTS}" V="${V:=1}" $MAKEFLAGS ${TARGETS:=all install check}

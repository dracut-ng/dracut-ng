#!/bin/bash

# script for integration testing invoked by GitHub Actions
# wraps configure && make
# assumes that it runs inside a CI container

export V=2
export stdloglvl=4
export sysloglvl=0

#ls -lRa /etc/dracut*
#ls -lRa /usr/lib/dracut/

#rm -rf  /usr/lib/dracut/dracut.conf.d/*

#echo 'hostonly="no"' > /usr/lib/dracut/dracut.conf.d/02-dist.conf
rm -rf /usr/lib/dracut/dracut.conf.d/02-dist.conf

#mv /usr/lib/dracut/dracut.conf.d /tmp
#rm -rf /usr/lib/dracut/*
#mv /tmp/dracut.conf.d /usr/lib/dracut/
#ls -la /usr/lib/dracut/dracut.conf.d/
echo hello

set -e
if [ "$V" = "2" ]; then set -x; fi

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

# disable building documentation by default
[ -z "$enable_documentation" ] && export enable_documentation=no

# shellcheck disable=SC2086
./configure $CONFIGURE_ARG

# treat warnings as error
# shellcheck disable=SC2086
CFLAGS="-Wextra -Werror" make TEST_RUN_ID="${TEST_RUN_ID:=$1}" TESTS="${TESTS:=$2}" V="${V:=1}" ${TARGETS:=all check}

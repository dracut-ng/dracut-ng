#!/usr/bin/env bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

# shellcheck disable=SC2034
TEST_DESCRIPTION="test skipcpio"

test_check() {
    if ! command -v 3cpio &> /dev/null && ! command -v cpio &> /dev/null; then
        echo "Neither 3cpio nor cpio are available."
        return 1
    fi

    (command -v find && command -v diff) &> /dev/null
}

cpio_create() {
    if command -v 3cpio &> /dev/null; then
        find . | sort | 3cpio --create
    else
        find . -print0 | sort -z | cpio -o --null -H newc
    fi
}

cpio_list_first() {
    local file="$1"
    if command -v 3cpio &> /dev/null; then
        3cpio --list --parts 1 "$file"
    else
        cpio --extract --quiet --list < "$file"
    fi
}

skipcpio_simple() {
    mkdir -p "$CPIO_TESTDIR/skipcpio_simple/first_archive"
    pushd "$CPIO_TESTDIR/skipcpio_simple/first_archive"

    for ((i = 0; i < 3; i++)); do
        echo "first archive file $i" >> ./"$i"
    done
    cpio_create > "$CPIO_TESTDIR/skipcpio_simple.cpio"
    popd

    mkdir -p "$CPIO_TESTDIR/skipcpio_simple/second_archive"
    pushd "$CPIO_TESTDIR/skipcpio_simple/second_archive"

    for ((i = 10; i < 13; i++)); do
        echo "second archive file $i" >> ./"$i"
    done

    cpio_create >> "$CPIO_TESTDIR/skipcpio_simple.cpio"
    popd

    cpio_list_first "$CPIO_TESTDIR/skipcpio_simple.cpio" \
        > "$CPIO_TESTDIR/skipcpio_simple.list"
    cat << EOF | diff - "$CPIO_TESTDIR/skipcpio_simple.list"
.
0
1
2
EOF

    if [ "$PKGLIBDIR" = "$basedir" ]; then
        skipcpio_path="${PKGLIBDIR}/src/skipcpio"
    else
        skipcpio_path="${PKGLIBDIR}"
    fi
    "$skipcpio_path"/skipcpio "$CPIO_TESTDIR/skipcpio_simple.cpio" \
        > "$CPIO_TESTDIR/skipped.cpio"
    cpio_list_first "$CPIO_TESTDIR/skipped.cpio" > "$CPIO_TESTDIR/skipcpio_simple.list"
    cat << EOF | diff - "$CPIO_TESTDIR/skipcpio_simple.list"
.
10
11
12
EOF
}

test_run() {
    set -x
    set -e

    skipcpio_simple

    return 0
}

test_setup() {
    CPIO_TESTDIR=$(mktemp --directory -p "$TESTDIR" cpio-test.XXXXXXXXXX)
    export CPIO_TESTDIR
    return 0
}

test_cleanup() {
    [ -d "${CPIO_TESTDIR-}" ] && rm -rf "$CPIO_TESTDIR"
    return 0
}

# shellcheck disable=SC1090
. "$testdir"/test-functions

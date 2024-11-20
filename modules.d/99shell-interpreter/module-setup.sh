#!/bin/bash
# This file is part of dracut.
# SPDX-License-Identifier: GPL-2.0-or-later

# Module dependency requirements.
depends() {
    # priority order
    shells='bash dash busybox'

    for shell in $shells; do
        if dracut_module_included "$shell"; then
            echo "$shell"
            return 0
        fi
    done

    shell=$(realpath /bin/sh)
    shell=${shell##*/}

    echo "$shell"
    return 0
}

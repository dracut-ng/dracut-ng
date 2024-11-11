#!/bin/sh

command -v getcmdline > /dev/null || . /lib/dracut-lib.sh

cm_generate_connections() {
    if getargbool 0 rd.neednet; then
        echo '[ -f /tmp/cm.done ]' > "$hookdir"/initqueue/finished/cm.sh
        mkdir -p /run/connman/initrd
        : > /run/connman/initrd/neednet # activate ConnMan services
    fi
}

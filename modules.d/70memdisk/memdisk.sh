#!/bin/sh

set -e

if ! [ -x /usr/bin/memdiskfind ]; then
    return
fi

if ! MEMDISK=$(/usr/bin/memdiskfind); then
    return
fi

# We found a memdisk, set up phram
# Sometimes "modprobe phram" can not successfully create /dev/mtd0.
# Have to try several times.
max_try=20
while [ ! -c /dev/mtd0 ] && [ "$max_try" -gt 0 ]; do
    modprobe phram "phram=memdisk,${MEMDISK}"
    sleep 0.2
    if [ -c /dev/mtd0 ]; then
        break
    else
        rmmod phram
    fi
    max_try=$((max_try - 1))
done

# Load mtdblock, the memdisk will be /dev/mtdblock0
modprobe mtdblock

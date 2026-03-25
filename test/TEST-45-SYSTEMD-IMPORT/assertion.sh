#!/bin/sh
set -eu

# required binaries: cat grep

if grep -Eq " / .*nodev" /proc/mounts; then
    echo "Error: / mounted with nodev flag." >> /run/failed
fi

if grep -Eq " / .*nosuid" /proc/mounts; then
    echo "Error: / mounted with nosuid flag." >> /run/failed
fi

# Dump /proc/mounts at the end if there were any failures for easier debugging
if [ -s /run/failed ]; then
    {
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> /proc/mounts >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        cat /proc/mounts
        echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< /proc/mounts <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
    } >> /run/failed
fi

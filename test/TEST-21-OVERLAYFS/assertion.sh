#!/bin/sh

if ! grep -q " overlay " /proc/mounts; then
    echo "overlay filesystem not found in /proc/mounts" >> /run/failed
fi

if ! echo > /test-overlay-write; then
    echo "overlay is not writable" >> /run/failed
fi

if grep -qE 'rd\.overlay=(LABEL|UUID|PARTUUID|PARTLABEL|/dev/)' /proc/cmdline; then
    if grep -q "rd.overlay=LABEL=NONEXISTENT" /proc/cmdline; then
        if grep -q "/run/overlayfs-backing" /proc/mounts; then
            echo "non-existent device should have fallen back to tmpfs but backing is mounted" >> /run/failed
        fi
    else
        if ! grep -q "/run/overlayfs-backing" /proc/mounts; then
            echo "persistent overlay device not mounted at /run/overlayfs-backing" >> /run/failed
        fi
    fi
else
    # tmpfs mode - verify persistent backing is NOT mounted
    if grep -q "/run/overlayfs-backing" /proc/mounts; then
        echo "tmpfs mode but persistent backing is mounted at /run/overlayfs-backing" >> /run/failed
    fi
fi

# Dump /proc/mounts at the end if there were any failures for easier debugging
if [ -s /run/failed ]; then
    {
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> /proc/mounts >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        cat /proc/mounts
        echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< /proc/mounts <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
    } >> /run/failed
fi

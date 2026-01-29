#!/bin/sh

# required binaries: grep sync

# Check for both new (rd.overlay) and deprecated (rd.live.overlay) parameter names
if grep -qE ' rd\.(live\.)?overlay=LABEL=persist ' /proc/cmdline; then
    # Writing to a file in the root filesystem lets test_run() verify that the autooverlay module successfully created
    # and formatted the overlay partition and that the dmsquash-live module used it when setting up the rootfs overlay.
    echo "dracut-autooverlay-success" > /overlay-marker
    # Ensure the marker is flushed to disk before shutdown
    sync /overlay-marker
fi

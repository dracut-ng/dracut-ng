#!/bin/sh

# required binaries: coredumpctl

# get the coredump (after switch_root)
COREDUMP=$(coredumpctl dump -1 --output=/dev/stdout)

if [ -z "$COREDUMP" ]; then
    echo "coredump expected, but none found" >> /run/failed
fi

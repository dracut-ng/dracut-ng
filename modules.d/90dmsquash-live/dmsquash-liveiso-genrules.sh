#!/bin/sh

if [ "${root%%:*}" = "liveiso" ]; then
    {
        # shellcheck disable=SC2016
        printf 'KERNEL=="loop-control", RUN+="/sbin/initqueue --settled --onetime --unique /sbin/dmsquash-live-root `/sbin/losetup -f --show %s`"\n' \
            "${root#liveiso:}"
    } >> "${udevrulesconfdir}"/99-liveiso-mount.rules
fi

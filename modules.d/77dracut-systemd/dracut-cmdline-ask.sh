#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh

getarg "rd.cmdline=ask" || exit 0

sleep 0.5
echo
sleep 0.5
echo
sleep 0.5
echo
echo
echo
echo
echo "Enter additional kernel command line parameter (end with ctrl-d or .)"
# In POSIX sh, read -p is undefined, but dash supports it
# shellcheck disable=SC3045
while read -r -p "> " ${BASH:+-e} line || [ -n "$line" ]; do
    [ "$line" = "." ] && break
    [ -n "$line" ] && printf -- "%s\n" "$line" >> /etc/cmdline.d/99-cmdline-ask.conf
done

exit 0

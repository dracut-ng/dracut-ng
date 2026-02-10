#!/bin/sh
# live net images - just like live images, but specified like:
# root=live:[url-to-backing-file]

[ -z "$root" ] && root=$(getarg root=)

command -v get_url_handler > /dev/null || . /lib/url-lib.sh

# live updates
updates=$(getarg live.updates=)
if [ -n "$updates" ]; then
    # make sure network comes up even if we're doing a local live device
    if [ -z "$netroot" ]; then
        echo > /tmp/net.ifaces
    fi
    echo "$updates" > /tmp/liveupdates.info
    echo '[ -e /tmp/liveupdates.done ]' > "$hookdir"/initqueue/finished/liveupdates.sh
fi

case "$root" in
    http://* | https://*)
        liveurl="${root}"
        ;;
    live:*)
        liveurl="${root#live:}"
        ;;
    *)
        return
        ;;
esac

# setting netroot to "livenet:..." makes "livenetroot" get run after ifup
if get_url_handler "$liveurl" > /dev/null; then
    info "livenet: root image at $liveurl"
    netroot="livenet:$liveurl"
    root="livenet" # quiet complaints from init
    # shellcheck disable=SC2034
    rootok=1
    wait_for_dev -n /dev/root
else
    info "livenet: no url handler for $liveurl"
fi

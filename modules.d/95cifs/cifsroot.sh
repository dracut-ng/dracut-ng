#!/bin/sh

command -v getarg > /dev/null || . /lib/dracut-lib.sh
command -v cifs_to_var > /dev/null || . /lib/cifs-lib.sh

[ "$#" = 3 ] || exit 1

# root is in the form root=cifs://user:pass@[server]/[folder] either from
# cmdline or dhcp root-path
#netif="$1"
root="$2"
NEWROOT="$3"

cifs_to_var "$root"

mount.cifs "//$server/$path" "$NEWROOT" -o "$options" && { [ -e /dev/root ] || ln -s null /dev/root; }

# inject new exit_if_exists
# shellcheck disable=SC2016
echo 'settle_exit_if_exists="--exit-if-exists=/dev/root"; rm -f -- "$job"' > "$hookdir"/initqueue/cifs.sh
# force udevsettle to break
: > "$hookdir"/initqueue/work

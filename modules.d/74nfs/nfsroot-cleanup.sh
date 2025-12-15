#!/bin/sh

command -v incol2 > /dev/null || . /lib/dracut-lib.sh
command -v nfsroot_to_var > /dev/null || . /lib/nfs-lib.sh

[ -n "$netroot" ] || return 0
nfsroot_to_var "$netroot"
str_starts "$nfs" "nfs" || return 0

[ -f /tmp/nfs.rpc_pipefs_path ] && read -r rpcpipefspath < /tmp/nfs.rpc_pipefs_path
[ -z "$rpcpipefspath" ] && rpcpipefspath=var/lib/nfs/rpc_pipefs

pid=$(pidof rpc.statd)
[ -n "$pid" ] && kill "$pid"

pid=$(pidof rpc.idmapd)
[ -n "$pid" ] && kill "$pid"

pid=$(pidof rpcbind)
[ -n "$pid" ] && kill "$pid"

if incol2 /proc/mounts /var/lib/nfs/rpc_pipefs; then
    # try to create the destination directory
    [ -d "$NEWROOT/$rpcpipefspath" ] \
        || mkdir -m 0755 -p "$NEWROOT/$rpcpipefspath" 2> /dev/null

    if [ -d "$NEWROOT/$rpcpipefspath" ]; then
        # mount --move does not seem to work???
        mount --bind /var/lib/nfs/rpc_pipefs "$NEWROOT/$rpcpipefspath"
        umount /var/lib/nfs/rpc_pipefs 2> /dev/null
    else
        umount /var/lib/nfs/rpc_pipefs 2> /dev/null
    fi
fi

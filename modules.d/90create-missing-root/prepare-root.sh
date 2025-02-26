#!/bin/bash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

NEWROOT=${NEWROOT:-'/sysroot'}

if ! [ -e "/run/create_new_root" ]; then
    exit 0
fi

mkdir -p /run/tmpfiles.d

# overlay files for usr
echo "d /.overlay 700 root root -
A /.overlay - - - - system_u:object_r:root_t:s0
d /.overlay/usr 700 root root -
A /.overlay/usr - - - - system_u:object_r:root_t:s0
d /.overlay/usr/upper 700 root root -
A /.overlay/usr/upper - - - - system_u:object_r:root_t:s0
d /.overlay/usr/work 700 root root -
A /.overlay/usr/work - - - - system_u:object_r:root_t:s0" > /run/tmpfiles.d/create-missing-root.conf

systemd-sysusers --root "$NEWROOT"
systemd-tmpfiles --root "$NEWROOT" --create
systemd-tmpfiles --root "$NEWROOT" --create /run/tmpfiles.d/create-missing-root.conf

# create symlinks
cd "$NEWROOT" || exit
ln -s usr/lib lib
ln -s usr/lib64 lib64
ln -s usr/sbin sbin
ln -s usr/bin bin
cd - || exit

mkdir -p "$NEWROOT"/etc
# TODO: copy or overlay?
cp -aZ "$NEWROOT"/usr/etc/* "$NEWROOT"/etc

# get rid of root in /etc/fstab since it is referring to an old one
sed -i '\|^[^#]\+\s\+/\s\+|d' "$NEWROOT"/etc/fstab

# TODO: selinux missing!

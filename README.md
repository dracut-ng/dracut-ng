# dracut-ng

dracut-ng is an event driven initramfs infrastructure.

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg)](https://dracut-ng.github.io/dracut-ng/developer/code_of_conduct.html)
[![Packaging status](https://repology.org/badge/tiny-repos/dracut.svg)](https://repology.org/project/dracut/versions)
[![latest packaged version(s)](https://repology.org/badge/latest-versions/dracut.svg)](https://repology.org/project/dracut/versions)

dracut-ng (the tool) is used to create an initramfs image by copying tools
and files from an installed system and combining it with the
dracut framework, usually found in /usr/lib/dracut/modules.d.

Unlike other implementations, dracut hard-codes as little
as possible into the initramfs. The initramfs has
(basically) one purpose in life -- getting the rootfs mounted so that
we can transition to the real rootfs.  This is all driven off of
device availability.  Therefore, instead of scripts hard-coded to do
various things, we depend on udev to create device nodes for us and
then when we have the rootfs's device node, we mount and carry on.
This helps to keep the time required in the initramfs as little as
possible so that things like a 5 second boot aren't made impossible as
a result of the very existence of an initramfs.

Most of the initramfs generation functionality in dracut is provided by a bunch
of generator modules that are sourced by the main dracut script to install
specific functionality into the initramfs.  They live in the modules.d
subdirectory, and use functionality provided by dracut-functions to do their
work.

# Documentation

Generated documentation from this source tree is available at
https://dracut-ng.github.io/

The [Wiki](https://github.com/dracut-ng/dracut-ng/wiki) is available to share
information.

# Releases

The release tarballs are [here](https://github.com/dracut-ng/dracut-ng/releases).

See [News](NEWS.md) for information about changes in the releases

# Contributing

Currently dracut-ng is developed on [github.com](https://github.com/dracut-ng/dracut-ng).

See the developer guide at https://dracut-ng.github.io/ for information on
reporting issues, contributing code via pull requests and guidelines for how to
get started contributing to dracut.

# Security

Security is taken very seriously.  Please do not report security issues in the
public tracker.  For guidelines on reporting security issues see the
[security](https://dracut-ng.github.io/dracut-ng/developer/security.html) guide.

# Chat and project interactions

Chat (Matrix):
 - https://matrix.to/#/#dracut-ng:matrix.org

See the [GitHub issue tracker](https://github.com/dracut-ng/dracut-ng/issues) for
things which still need to be done. This is also the main place used for
discussions.

# License

Licensed under the GPLv2

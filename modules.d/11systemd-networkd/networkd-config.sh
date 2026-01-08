#!/bin/sh

command -v getcmdline > /dev/null || . /lib/dracut-lib.sh

# Just in case we're running before it
systemctl start systemd-network-generator.service

# Customizations for systemd-network-generator generated networks.
# We need to request certain DHCP options, and there is no way to
# tell the generator to add those.
for f in /run/systemd/network/*.network; do
    [ -f "$f" ] || continue

    {
        echo "[DHCPv4]"
        echo "ClientIdentifier=mac"
        echo "RequestOptions=17"
        echo "[DHCPv6]"
        echo "RequestOptions=59 60"
    } >> "$f"

    # at least one was generated
    : > /run/systemd/network/generated
done

# Add the default network if none was generated
if ! [ -e /run/systemd/network/generated ]; then
    cp -a /usr/lib/99-default.network /run/systemd/network/zzzz-dracut-default.network
else
    rm /run/systemd/network/generated
fi

# Just in case networkd was already running
systemctl try-reload-or-restart systemd-networkd.service

if [ -n "$netroot" ] || [ -e /tmp/net.ifaces ]; then
    echo rd.neednet >> /etc/cmdline.d/20-networkd.conf
fi

if getargbool 0 rd.neednet; then
    mkdir -p /run/networkd/initrd
    : > /run/networkd/initrd/neednet
fi

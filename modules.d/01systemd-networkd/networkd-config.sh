#!/bin/sh

type getcmdline > /dev/null 2>&1 || . /lib/dracut-lib.sh

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

    # Remove the default network if at least one was generated
    rm -f "$systemdnetworkconfdir"/zzzz-dracut-default.network
done

# Just in case networkd was already running
systemctl try-reload-or-restart systemd-networkd.service

if [ -n "$netroot" ] || [ -e /tmp/net.ifaces ]; then
    echo rd.neednet >> /etc/cmdline.d/networkd.conf
fi

if getargbool 0 rd.neednet; then
    mkdir -p /run/networkd/initrd
    : > /run/networkd/initrd/neednet
fi

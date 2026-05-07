#!/bin/sh

command -v source_hook > /dev/null || . /lib/dracut-lib.sh

for ifpath in /sys/class/net/*; do
    ifname="${ifpath##*/}"

    # shellcheck disable=SC2015
    [ "$ifname" != "lo" ] && [ -e "$ifpath" ] && [ ! -e /tmp/networkd."$ifname".done ] || continue

    if /usr/lib/systemd/systemd-networkd-wait-online --timeout=0.000001 --interface="$ifname" 2> /dev/null; then
        leases_file="/run/systemd/netif/leases/$(cat "$ifpath"/ifindex)"
        dhcpopts_file="/tmp/dhclient.${ifname}.dhcpopts"
        if [ -r "$leases_file" ]; then
            grep -E "^(NEXT_SERVER|ROOT_PATH)=" "$leases_file" \
                | sed -e "s/NEXT_SERVER=/new_next_server='/" \
                    -e "s/ROOT_PATH=/new_root_path='/" \
                    -e "s/$/'/" > "$dhcpopts_file" || true

            # systemd-networkd mixes IPv4 and IPv6 addresses under
            # the same NTP= property, but dhclient has two properties
            # for that: new_ntp_servers and new_dhcp6_ntp_servers
            ntp_ipv4=
            ntp_ipv6=
            ntp_servers=$(sed -n "s/^NTP=\(.*\)/\1/p" "$leases_file")
            for i in $ntp_servers; do
                case "$i" in
                    *.*.*.*)
                        ntp_ipv4="$ntp_ipv4${ntp_ipv4:+ }$i"
                        ;;
                    *)
                        # hostnames are only allowed in DHCPv6
                        ntp_ipv6="$ntp_ipv6${ntp_ipv6:+ }$i"
                        ;;
                esac
            done
            if [ -n "$ntp_ipv4" ]; then
                echo "new_ntp_servers=$ntp_ipv4" >> "$dhcpopts_file"
            fi
            if [ -n "$ntp_ipv6" ]; then
                echo "new_dhcp6_ntp_servers=$ntp_ipv6" >> "$dhcpopts_file"
            fi
        fi

        source_hook initqueue/online "$ifname"
        /sbin/netroot "$ifname"

        : > /tmp/networkd."$ifname".done
    fi
done

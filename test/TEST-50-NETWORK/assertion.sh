#!/bin/sh

# required binaries: grep ip

# Get the output of 'ip addr show' and filter out lo interface
ip_output=$(ip -o -4 addr show | grep -v ': lo')

# Extract the line containing "inet"
inet_line="${ip_output##*inet }"
inet_line="${inet_line%% brd*}" # Remove everything after "brd" if it exists

# Extract the IP address by removing the subnet mask
ip_address="${inet_line%%/*}"

# https://www.qemu.org/docs/master/system/devices/net.html#using-the-user-mode-network-stack
# The qemu DHCP server assign addresses to the hosts starting from 10.0.2.15
# We run the VM only with one network interface, so testing for 10.0.2.15 is safe

if [ "$ip_address" != "10.0.2.15" ]; then
    # fail the test
    echo "ip addr show" >> /run/failed
    ip addr show >> /run/failed
fi

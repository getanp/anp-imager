#!/bin/sh
# udhcpc script for BusyBox-only initramfs
set -eu

case "$1" in
  deconfig)
    /bin/busybox ifconfig "$interface" 0.0.0.0
    ;;

  bound|renew)
    echo "[udhcpc] configuring $interface ip=$ip mask=${subnet:-$mask} gw=$router dns=$dns"

    NM="${subnet:-${mask:-255.255.255.0}}"

    /bin/busybox ifconfig "$interface" "$ip" netmask "$NM" up
    [ -n "${router:-}" ] && /bin/busybox route add default gw "$router" "$interface"

    mkdir -p /etc
    : > /etc/resolv.conf
    for ns in $dns; do
      echo "nameserver $ns" >> /etc/resolv.conf
    done
    ;;
esac

exit 0

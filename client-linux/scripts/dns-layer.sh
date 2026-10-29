#!/bin/bash
# Fail-closed DNS layer (Linux equivalent of the macOS /etc/resolver files).
# A persistent dummy link carries systemd-resolved "routing domains" for the
# six Anthropic apexes, with the sing-box DNS listener on loopback as its only
# server. Names under those domains are never sent to any other DNS server.
# When sing-box is down the listener is closed and those names fail to resolve.
#   dns-layer.sh up | down | status
set -eu
. "$(dirname "$0")/common.sh"
need_root
command -v resolvectl >/dev/null || { echo "resolvectl not found: systemd-resolved is required" >&2; exit 1; }
case "${1:-}" in
  up)
    dns_layer_up || ip link add "$DNS_LINK" type dummy
    ip addr replace "$DNS_LINK_ADDR" dev "$DNS_LINK"
    ip link set "$DNS_LINK" up
    resolvectl dns "$DNS_LINK" "$DNS_LISTEN"
    # shellcheck disable=SC2046
    resolvectl domain "$DNS_LINK" $(for d in $DOMAINS; do printf '~%s ' "$d"; done)
    resolvectl default-route "$DNS_LINK" false
    resolvectl flush-caches
    echo "dns layer UP: $DOMAINS -> $DNS_LISTEN via $DNS_LINK"
    ;;
  down)
    if dns_layer_up; then
      resolvectl revert "$DNS_LINK" 2>/dev/null || true
      ip link del "$DNS_LINK"
    fi
    resolvectl flush-caches
    echo "dns layer DOWN: Anthropic names resolve normally"
    ;;
  status)
    dns_layer_up && resolvectl status "$DNS_LINK" || { echo "dns layer not up"; exit 1; }
    ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac

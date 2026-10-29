#!/bin/bash
# Leak guard (Linux, nftables). Blocks every outgoing or forwarded packet to
# Anthropic addresses unless it leaves through this project's TUN interface.
# Independent of sing-box: when the daemon is down, or another VPN owns the
# routes, nothing reaches Anthropic directly.
#   guard.sh up | refresh | down | status
#   up      load the table (static ranges + last known dynamic addresses)
#   refresh replace the dynamic addresses with the current list (via the tunnel)
#   down    remove the table (only tunnel-down.sh and uninstall.sh do this)
set -eu
. "$(dirname "$0")/common.sh"
need_root
command -v nft >/dev/null || { echo "nft not found: install the nftables package" >&2; exit 1; }
DYN="$VAR/guard-dynamic.txt"
NEW="$VAR/guard-dynamic.new"
STATUS="$ETC/guard-status"
# one run at a time (the timer and a manual call may overlap)
install -d -m 700 "$VAR"
exec 9>"$VAR/guard.lock"
flock 9

load_dynamic() {
  v4=$(grep -E '^[0-9.]+$' "$DYN" 2>/dev/null | paste -sd, - || true)
  v6=$(grep -E ':' "$DYN" 2>/dev/null | paste -sd, - || true)
  printf 'flush set inet %s dyn4\nflush set inet %s dyn6\n' "$GUARD_TABLE" "$GUARD_TABLE"
  if [ -n "$v4" ]; then printf 'add element inet %s dyn4 { %s }\n' "$GUARD_TABLE" "$v4"; fi
  if [ -n "$v6" ]; then printf 'add element inet %s dyn6 { %s }\n' "$GUARD_TABLE" "$v6"; fi
}

write_status() {
  n=$(grep -c . "$DYN" 2>/dev/null || true)
  printf '%s %s %s\n' "$1" "${n:-0}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS"
  chmod 644 "$STATUS"
}

case "${1:-}" in
  up)
    install -d -m 700 "$VAR"; touch "$DYN"
    {
      # "table ...; delete table ..." makes the reload atomic and idempotent
      printf 'table inet %s\ndelete table inet %s\n' "$GUARD_TABLE" "$GUARD_TABLE"
      cat <<NFT
table inet $GUARD_TABLE {
  set static4 { type ipv4_addr; flags interval; elements = { $GUARD_STATIC4 } }
  set static6 { type ipv6_addr; flags interval; elements = { $GUARD_STATIC6 } }
  set dyn4 { type ipv4_addr; }
  set dyn6 { type ipv6_addr; }
  chain guard_output {
    type filter hook output priority -10; policy accept;
    oifname "$TUN_IF" accept
    ip daddr @static4 counter reject
    ip daddr @dyn4 counter reject
    ip6 daddr @static6 counter reject
    ip6 daddr @dyn6 counter reject
  }
  chain guard_forward {
    type filter hook forward priority -10; policy accept;
    oifname "$TUN_IF" accept
    ip daddr @static4 counter reject
    ip daddr @dyn4 counter reject
    ip6 daddr @static6 counter reject
    ip6 daddr @dyn6 counter reject
  }
}
NFT
      load_dynamic
    } | nft -f -
    write_status on
    echo "leak guard UP: Anthropic addresses leave only through $TUN_IF"
    ;;
  refresh)
    guard_up || { echo "guard table not loaded" >&2; exit 1; }
    if bash "$BIN/guard-ips.sh" "$ETC/clash-api.secret" > "$NEW" && [ -s "$NEW" ]; then
      install -m 600 "$NEW" "$DYN"
      load_dynamic | nft -f -
      write_status on
      echo "leak guard refreshed: $(grep -c . "$DYN") dynamic addresses"
    else
      echo "local API unavailable or empty answer: kept the last list" >&2
    fi
    ;;
  down)
    nft delete table inet "$GUARD_TABLE" 2>/dev/null || true
    write_status off 2>/dev/null || true
    echo "leak guard DOWN"
    ;;
  status)
    nft list table inet "$GUARD_TABLE" 2>/dev/null || { echo "leak guard not loaded"; exit 1; }
    ;;
  *) echo "usage: $0 up|refresh|down|status" >&2; exit 2 ;;
esac

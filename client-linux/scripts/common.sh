#!/bin/bash
# Shared definitions for anthropic-tunnel Linux client scripts. Sourced, not run.
UNIT="anthropic-tunnel.service"
DNS_UNIT="anthropic-tunnel-dns.service"
BASE="/usr/local/anthropic-tunnel"
BIN="$BASE/bin"
ETC="$BASE/etc"
VAR="$BASE/var"
UNIT_DIR="/etc/systemd/system"
SUDOERS="/etc/sudoers.d/anthropic-tunnel"
NM_CONF="/etc/NetworkManager/conf.d/anthropic-tunnel.conf"
DNS_LINK="anthropic-dns0"          # dummy link that carries the resolved routing domains
DNS_LINK_ADDR="172.30.250.9/32"      # resolved ignores a link without an address
DNS_LISTEN="172.30.250.9:5553"        # sing-box "direct" inbound on the dummy link's own address: resolved binds the query to that link, so only the six domains ever reach it
TUN_IF="anthropic-tun0"
TUN_ADDR="172.30.250.1"
DOMAINS="anthropic.com claude.ai claude.com claude.app claudeusercontent.com claudemcpcontent.com"
GUARD_UNIT="anthropic-tunnel-guard.service"
GUARD_TIMER="anthropic-tunnel-guard-refresh.timer"
GUARD_TABLE="anthropic_guard"
# Anthropic's own ranges and sing-box's fake-IP ranges: nothing to them may leave except through the TUN
GUARD_STATIC4="160.79.104.0/21, 198.18.0.0/15"
GUARD_STATIC6="2607:6bc0::/48, 2001:2::/48"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }; }
daemon_enabled() { systemctl is-enabled --quiet "$UNIT" 2>/dev/null; }
daemon_active()  { systemctl is-active  --quiet "$UNIT" 2>/dev/null; }
dns_layer_up()   { ip link show "$DNS_LINK" >/dev/null 2>&1; }
guard_up()       { nft list table inet "$GUARD_TABLE" >/dev/null 2>&1; }

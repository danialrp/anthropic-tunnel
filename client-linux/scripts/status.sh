#!/bin/bash
# Read-only status; no root needed.
. "$(dirname "$0")/common.sh"
printf 'daemon enabled: '; daemon_enabled && echo yes || echo no
printf 'process       : '; daemon_active && echo running || echo "not running"
printf 'dns layer     : '
if dns_layer_up; then
  n=$(resolvectl status "$DNS_LINK" 2>/dev/null | grep -o '~[a-z.]*' | wc -l | tr -d ' ')
  echo "up ($n/6 routing domains)"
else
  echo down
fi
printf 'tun interface : '; ip -4 addr show "$TUN_IF" 2>/dev/null | grep -q "inet $TUN_ADDR" && echo up || echo down
printf 'claude.ai ->  '; getent ahostsv4 claude.ai 2>/dev/null | awk '{print $1; exit}'; echo
printf 'api check     : '; curl -s --max-time 8 -o /dev/null -w '%{http_code}\n' https://api.anthropic.com/v1/models || echo fail

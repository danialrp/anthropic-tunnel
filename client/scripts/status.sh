#!/bin/bash
# Read-only status; no root needed.
. "$(dirname "$0")/common.sh"
printf 'daemon loaded : '; launchctl print "system/$LABEL" >/dev/null 2>&1 && echo yes || echo no
printf 'process       : '; pgrep -x sing-box >/dev/null && echo running || echo "not running"
printf 'resolver files: '; n=0; for d in $DOMAINS; do [ -f "/etc/resolver/$d" ] && n=$((n+1)); done; echo "$n/6"
printf 'leak guard    : '; if [ -r "$ETC/guard-status" ]; then read -r g n t u < "$ETC/guard-status"; echo "$g (pass via ${u:--}, $n extra addresses, updated $t)"; else echo "not installed"; fi
printf 'tun interface : '; ifconfig 2>/dev/null | grep -q "inet 172.19.0.1" && echo up || echo down
printf 'claude.ai ->  '; dscacheutil -q host -a name claude.ai 2>/dev/null | awk '/ip_address/{print $2; exit}'
printf 'api check     : '; curl -s --max-time 8 -o /dev/null -w '%{http_code}\n' https://api.anthropic.com/v1/models || echo fail

#!/bin/bash
# Shared definitions for anthropic-tunnel client scripts. Sourced, not run.
LABEL="local.anthropic-tunnel"
BASE="/usr/local/anthropic-tunnel"
BIN="$BASE/bin"
ETC="$BASE/etc"
VAR="$BASE/var"
LOGDIR="/var/log/anthropic-tunnel"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SUDOERS="/etc/sudoers.d/anthropic-tunnel"
TUN_DNS="172.19.0.2"
DOMAINS="anthropic.com claude.ai claude.com claude.app claudeusercontent.com claudemcpcontent.com"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }; }

resolver_add() {
  for d in $DOMAINS; do printf 'nameserver %s\n' "$TUN_DNS" > "/etc/resolver/$d"; chmod 644 "/etc/resolver/$d"; done
}
resolver_remove() {
  for d in $DOMAINS; do rm -f "/etc/resolver/$d"; done
}
daemon_loaded() { launchctl print "system/$LABEL" >/dev/null 2>&1; }

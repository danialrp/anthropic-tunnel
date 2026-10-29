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
TUN_ADDR="172.19.0.1"
# leak guard: our pf anchor under Apple's com.apple/* hook, and its two launchd jobs
GUARD_ANCHOR="com.apple/250.anthropic-tunnel"
GUARD_LABEL="local.anthropic-tunnel.guard"
GUARD_REFRESH_LABEL="local.anthropic-tunnel.guard-refresh"
# Anthropic's own ranges and sing-box's fake-IP ranges: nothing to them may leave except through our utun
GUARD_STATIC="160.79.104.0/21, 198.18.0.0/15, 2607:6bc0::/48, 2001:2::/48"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }; }

resolver_add() {
  for d in $DOMAINS; do printf 'nameserver %s\n' "$TUN_DNS" > "/etc/resolver/$d"; chmod 644 "/etc/resolver/$d"; done
}
resolver_remove() {
  for d in $DOMAINS; do rm -f "/etc/resolver/$d"; done
}
daemon_loaded() { launchctl print "system/$LABEL" >/dev/null 2>&1; }
job_loaded()    { launchctl print "system/$1" >/dev/null 2>&1; }
guard_start() {
  for l in "$GUARD_LABEL" "$GUARD_REFRESH_LABEL"; do
    [ -f "/Library/LaunchDaemons/$l.plist" ] || continue
    job_loaded "$l" || launchctl bootstrap system "/Library/LaunchDaemons/$l.plist"
  done
}
guard_stop() {
  for l in "$GUARD_LABEL" "$GUARD_REFRESH_LABEL"; do job_loaded "$l" && launchctl bootout "system/$l" || true; done
  [ -x "$BIN/guard.sh" ] && bash "$BIN/guard.sh" down >/dev/null || true
}

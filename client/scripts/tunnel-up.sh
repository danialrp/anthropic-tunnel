#!/bin/bash
# Enable the tunnel: load the launchd daemon and point Anthropic DNS at it.
set -eu
. "$(dirname "$0")/common.sh"
need_root
[ -f "$PLIST" ] || { echo "not installed: $PLIST missing (run install.sh)" >&2; exit 1; }
resolver_add
if daemon_loaded; then
  echo "daemon already loaded"
else
  launchctl bootstrap system "$PLIST"
  echo "daemon loaded"
fi
guard_start
echo "tunnel UP: leak guard on, Anthropic DNS -> $TUN_DNS, daemon $LABEL running"

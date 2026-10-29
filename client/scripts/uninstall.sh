#!/bin/bash
# Remove everything install.sh created. The Homebrew sing-box stays.
#   sudo bash client/scripts/uninstall.sh
# Body is a function so bash has parsed the whole file before it deletes
# the installed copy of this script.
set -eu
. "$(dirname "$0")/common.sh"
main() {
  need_root
  guard_stop
  rm -f "/Library/LaunchDaemons/$GUARD_LABEL.plist" "/Library/LaunchDaemons/$GUARD_REFRESH_LABEL.plist"
  if daemon_loaded; then launchctl bootout "system/$LABEL" || true; fi
  rm -f "$PLIST" "$SUDOERS"
  resolver_remove
  dscacheutil -flushcache 2>/dev/null || true
  rm -rf "$BASE" "$LOGDIR" "/Library/Application Support/anthropic-tunnel"
  echo "uninstalled: daemon, leak guard (pf anchor, jobs), plists, sudoers, resolver files, $BASE, $LOGDIR removed"
  printf 'tun interface : '
  if ifconfig 2>/dev/null | grep -q "inet 172.19.0.1"; then echo "STILL UP (check manually)"; else echo down; fi
}
main "$@"

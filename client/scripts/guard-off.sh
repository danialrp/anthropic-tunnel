#!/bin/bash
# Manual revert of the leak guard only (the tunnel keeps running):
#   sudo bash /usr/local/anthropic-tunnel/bin/guard-off.sh
# Turn it back on with tunnel-up.sh or guard-install.sh.
set -u
. "$(dirname "$0")/common.sh"
need_root
for l in "$GUARD_LABEL" "$GUARD_REFRESH_LABEL"; do launchctl bootout "system/$l" 2>/dev/null || true; done
/sbin/pfctl -q -a "$GUARD_ANCHOR" -F all 2>/dev/null || true
[ -x "$BIN/guard.sh" ] && bash "$BIN/guard.sh" down >/dev/null 2>&1 || true
echo "leak guard OFF (anchor $GUARD_ANCHOR flushed, jobs unloaded)"

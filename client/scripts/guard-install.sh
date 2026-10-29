#!/bin/bash
# Install or update the leak guard on a Mac where the client is installed.
#   sudo bash client/scripts/guard-install.sh
# Updates the control scripts and adds the guard; never restarts the tunnel
# daemon. After switching the guard on it runs a self-test and removes the
# guard again by itself if Anthropic stops answering through the tunnel.
# Manual revert at any time: sudo bash /usr/local/anthropic-tunnel/bin/guard-off.sh
set -eu
. "$(dirname "$0")/common.sh"
need_root
REPO=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$PLIST" ] || { echo "client not installed: run client/scripts/install.sh first" >&2; exit 1; }

for s in common.sh guard.sh guard-off.sh tunnel-up.sh tunnel-down.sh tunnel-restart.sh status.sh uninstall.sh; do
  install -o root -g wheel -m 755 "$REPO/client/scripts/$s" "$BIN/$s"
done
install -o root -g wheel -m 755 "$REPO/shared/guard-ips.sh" "$BIN/guard-ips.sh"
for l in "$GUARD_LABEL" "$GUARD_REFRESH_LABEL"; do
  plutil -lint -s "$REPO/client/launchd/$l.plist"
  install -o root -g wheel -m 644 "$REPO/client/launchd/$l.plist" "/Library/LaunchDaemons/$l.plist"
done

if ! daemon_loaded; then
  echo "guard installed; the tunnel is off (grey), so the guard stays off until tunnel-up.sh"
  exit 0
fi

guard_start
bash "$BIN/guard.sh" apply
bash "$BIN/guard.sh" refresh
bash "$BIN/guard.sh" apply
echo "--- self-test"
rc=0; bash "$BIN/guard.sh" selftest || rc=$?
case "$rc" in
  0) echo "leak guard ON and verified"; bash "$BIN/guard.sh" status | head -12 ;;
  2) echo "Anthropic does not answer through the tunnel with the guard on: rolling back" >&2
     guard_stop; echo "guard removed; tunnel unchanged" >&2; exit 1 ;;
  3) echo "WARNING: the guard is loaded but the probe was not refused; check: sudo bash $BIN/guard.sh status" >&2; exit 1 ;;
  *) echo "self-test error $rc" >&2; exit 1 ;;
esac

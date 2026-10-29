#!/bin/bash
# Restart the running daemon (launchd keeps it loaded).
set -eu
. "$(dirname "$0")/common.sh"
need_root
if daemon_loaded; then
  launchctl kickstart -k "system/$LABEL"
  # the utun number may change: re-point the guard at once instead of waiting for its 5 s cycle
  if job_loaded "$GUARD_LABEL"; then sleep 2; bash "$BIN/guard.sh" apply || true; fi
  echo "daemon restarted"
else
  echo "daemon not loaded; use tunnel-up.sh" >&2; exit 1
fi

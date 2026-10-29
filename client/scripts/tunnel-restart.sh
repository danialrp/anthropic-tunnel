#!/bin/bash
# Restart the running daemon (launchd keeps it loaded).
set -eu
. "$(dirname "$0")/common.sh"
need_root
if daemon_loaded; then
  launchctl kickstart -k "system/$LABEL"
  echo "daemon restarted"
else
  echo "daemon not loaded; use tunnel-up.sh" >&2; exit 1
fi

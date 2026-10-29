#!/bin/bash
# Restart the running daemon (systemd keeps it enabled).
set -eu
. "$(dirname "$0")/common.sh"
need_root
if daemon_enabled; then
  systemctl restart "$UNIT"
  echo "daemon restarted"
else
  echo "daemon not enabled; use tunnel-up.sh" >&2; exit 1
fi

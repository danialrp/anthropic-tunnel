#!/bin/bash
# Enable the tunnel: DNS layer + daemon, now and at every boot.
set -eu
. "$(dirname "$0")/common.sh"
need_root
[ -f "$UNIT_DIR/$UNIT" ] || { echo "not installed: $UNIT_DIR/$UNIT missing (run install.sh)" >&2; exit 1; }
systemctl enable --now --quiet "$GUARD_UNIT" "$DNS_UNIT" "$UNIT" "$GUARD_TIMER"
echo "tunnel UP: leak guard on, Anthropic DNS -> $DNS_LISTEN, $UNIT running"

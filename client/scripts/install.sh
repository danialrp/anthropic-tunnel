#!/bin/bash
# Install the anthropic-tunnel client on this Mac. Run with sudo from the repo:
#   sudo bash client/scripts/install.sh
# Idempotent: re-running updates binary, config, scripts and restarts the daemon.
set -eu
. "$(dirname "$0")/common.sh"
need_root
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SRC_BIN=$(command -v sing-box || echo /opt/homebrew/bin/sing-box)
[ -x "$SRC_BIN" ] || { echo "sing-box binary not found (brew install sing-box)" >&2; exit 1; }
[ -s "$REPO/client/sing-box/config.json" ] || { echo "rendered config missing: run bash client/render.sh first (as your user)" >&2; exit 1; }
"$SRC_BIN" check -c "$REPO/client/sing-box/config.json"

install -d -o root -g wheel -m 755 "$BASE" "$BIN" "$ETC" "$LOGDIR"
install -d -o root -g wheel -m 700 "$VAR"
install -o root -g wheel -m 755 "$SRC_BIN" "$BIN/sing-box"
install -o root -g wheel -m 600 "$REPO/client/sing-box/config.json" "$ETC/config.json"
for s in common.sh tunnel-up.sh tunnel-down.sh tunnel-restart.sh status.sh uninstall.sh; do
  install -o root -g wheel -m 755 "$REPO/client/scripts/$s" "$BIN/$s"
done
install -o root -g wheel -m 644 "$REPO/client/launchd/$LABEL.plist" "$PLIST"

# indicator inputs: Clash API secret and server IP, readable by the installing user's group
OWNER="${SUDO_USER:?run with sudo from your own user, not as root}"
grep -oE '"secret": *"[^"]*"' "$ETC/config.json" | head -1 | sed -E 's/.*"secret": *"([^"]*)"/\1/' > "$ETC/clash-api.secret"
grep -oE '"address": *"[^"]+", *"port": *[0-9]+' "$ETC/config.json" | head -1 | sed -E 's/.*"address": *"([^"]+)".*/\1/' > "$ETC/server-ip"   # the WireGuard peer address
chown "root:$(id -gn "$OWNER")" "$ETC/clash-api.secret" "$ETC/server-ip"; chmod 640 "$ETC/clash-api.secret" "$ETC/server-ip"

# sudoers: menu bar may run exactly these three scripts without a password
TMP=$(mktemp)
printf '%s ALL=(root) NOPASSWD: %s/tunnel-up.sh, %s/tunnel-down.sh, %s/tunnel-restart.sh\n' \
  "$OWNER" "$BIN" "$BIN" "$BIN" > "$TMP"
visudo -c -f "$TMP" >/dev/null
install -o root -g wheel -m 440 "$TMP" "$SUDOERS"; rm -f "$TMP"

# stop any foreground sing-box so the daemon can own the TUN and cache
pkill -x sing-box 2>/dev/null && sleep 2 || true

if daemon_loaded; then launchctl bootout "system/$LABEL"; sleep 1; fi
launchctl bootstrap system "$PLIST"
resolver_add
sleep 3
echo "--- installed. version: $("$BIN/sing-box" version | head -1)"
bash "$BIN/status.sh"

#!/bin/bash
# Apply a validated local config without stopping the persistent DNS layer.
# Run from this checkout with sudo; retains a root-only rollback config.
set -eu
. "$(dirname "$0")/common.sh"
need_root
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SOURCE="$REPO/client-linux/sing-box/config.json"
BACKUP="$ETC/config.before-profiles.json"
[ -f "$ETC/config.json" ] || { echo "Install the Linux client first" >&2; exit 1; }
WAS_ACTIVE=no
if systemctl is-active --quiet "$UNIT"; then WAS_ACTIVE=yes; fi
"$BIN/sing-box" check -c "$SOURCE"
if python3 - "$SOURCE" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
sys.exit(0 if any(o.get("tag") == "vless-xhttp-80" for o in config["outbounds"]) else 1)
PY
then
  if [ "$WAS_ACTIVE" = yes ]; then
    bash "$REPO/client-linux/scripts/install-xhttp.sh"
  else
    bash "$REPO/client-linux/scripts/install-xhttp.sh" --no-start
  fi
fi
install -o root -g root -m 600 "$ETC/config.json" "$BACKUP"
install -o root -g root -m 600 "$SOURCE" "$ETC/config.next.json"
mv "$ETC/config.next.json" "$ETC/config.json"
if [ "$WAS_ACTIVE" != yes ]; then
  echo "Profiles installed. The tunnel remains off."
  echo "Turn off any other VPN TUN, then use Connect in the tray."
  exit 0
fi
STARTED=yes
systemctl restart "$UNIT" || STARTED=no
sleep 3
if [ "$STARTED" != yes ] || ! systemctl is-active --quiet "$UNIT"; then
  install -o root -g root -m 600 "$BACKUP" "$ETC/config.json"
  systemctl restart "$UNIT"
  echo "New daemon failed to stay running; previous config restored" >&2
  exit 1
fi
echo "Applied profiles; previous config saved as $BACKUP"
bash "$BIN/status.sh"

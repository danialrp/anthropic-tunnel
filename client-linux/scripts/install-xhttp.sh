#!/bin/bash
# Optional, isolated Xray helper. No TUN, DNS changes or server writes.
set -eu
. "$(dirname "$0")/common.sh"
need_root
case "${1:-}" in
  ""|--no-start) ;;
  *) echo "usage: $0 [--no-start]" >&2; exit 2 ;;
esac
REPO=$(cd "$(dirname "$0")/../.." && pwd)
XRAY="$REPO/client-linux/bin/xray"
CONFIG="$REPO/private/secrets/xhttp-client.json"
# Exact amd64 binary copied over authenticated SSH from the configured server:
# Xray 26.3.27, revision d2758a0, verified on 2026-10-29.
EXPECTED="8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed"
[ "$(sha256sum "$XRAY" | awk '{print $1}')" = "$EXPECTED" ] || {
  echo "Xray binary missing or checksum mismatch" >&2; exit 1;
}
"$XRAY" run -test -config "$CONFIG" >/dev/null
install -o root -g root -m 755 "$XRAY" "$BIN/xray"
install -o root -g root -m 600 "$CONFIG" "$ETC/xhttp.json"
install -o root -g root -m 644 "$REPO/client-linux/systemd/anthropic-tunnel-xhttp.service" "$UNIT_DIR/anthropic-tunnel-xhttp.service"
install -d -o root -g root -m 755 "$UNIT_DIR/$UNIT.d"
printf '[Unit]\nWants=anthropic-tunnel-xhttp.service\nAfter=anthropic-tunnel-xhttp.service\n' > "$UNIT_DIR/$UNIT.d/xhttp.conf"
systemctl daemon-reload
if [ "${1:-}" = --no-start ]; then
  echo "XHTTP helper installed; starts with the tunnel through its Wants dependency"
  exit 0
fi
systemctl restart anthropic-tunnel-xhttp.service
sleep 1
systemctl is-active --quiet anthropic-tunnel-xhttp.service || {
  echo "XHTTP helper failed; inspect journalctl -u anthropic-tunnel-xhttp" >&2; exit 1;
}
echo "XHTTP helper active; authenticated SOCKS on loopback only"

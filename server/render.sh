#!/bin/sh
# Render server/sing-box/config.json from the template + private/secrets/.
# Usage: sh server/render.sh   (run from repo root or anywhere)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEC="$ROOT/private/secrets"   # operator data, git-ignored (CLAUDE.md rule 4)
TPL="$ROOT/server/sing-box/config.template.json"
OUT="$ROOT/server/sing-box/config.json"
for f in wg-server.key wg-client.pub wg-linux.pub wg-psk.key vless-uuid reality.key reality-shortid; do
  [ -s "$SEC/$f" ] || { echo "missing $SEC/$f" >&2; exit 1; }
done
umask 077
sed \
  -e "s|__WG_SERVER_KEY__|$(tr -d '\n' < "$SEC/wg-server.key")|" \
  -e "s|__WG_CLIENT_PUB__|$(tr -d '\n' < "$SEC/wg-client.pub")|" \
  -e "s|__WG_LINUX_PUB__|$(tr -d '\n' < "$SEC/wg-linux.pub")|" \
  -e "s|__WG_PSK__|$(tr -d '\n' < "$SEC/wg-psk.key")|" \
  -e "s|__VLESS_UUID__|$(tr -d '\n' < "$SEC/vless-uuid")|" \
  -e "s|__REALITY_KEY__|$(tr -d '\n' < "$SEC/reality.key")|" \
  -e "s|__REALITY_SHORTID__|$(tr -d '\n' < "$SEC/reality-shortid")|" \
  "$TPL" > "$OUT"
grep -q '__' "$OUT" && { echo "unrendered placeholder left in $OUT" >&2; exit 1; }
echo "rendered $OUT"

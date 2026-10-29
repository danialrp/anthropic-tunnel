#!/bin/bash
# Render client/sing-box/config.json from the template + private/secrets/.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEC="$ROOT/private/secrets"   # operator data, git-ignored (CLAUDE.md rule 4)
TPL="$ROOT/client/sing-box/config.template.json"
OUT="$ROOT/client/sing-box/config.json"
for f in wg-client.key wg-server.pub wg-psk.key clash-api.secret server.env vless-uuid reality.pub reality-shortid; do
  [ -s "$SEC/$f" ] || { echo "missing $SEC/$f" >&2; exit 1; }
done
# shellcheck disable=SC1090
. "$SEC/server.env"
umask 077
sed \
  -e "s|__WG_CLIENT_KEY__|$(tr -d '\n' < "$SEC/wg-client.key")|" \
  -e "s|__WG_SERVER_PUB__|$(tr -d '\n' < "$SEC/wg-server.pub")|" \
  -e "s|__WG_PSK__|$(tr -d '\n' < "$SEC/wg-psk.key")|" \
  -e "s|__SERVER_IP__|$SERVER_IP|" \
  -e "s|__CLASH_SECRET__|$(tr -d '\n' < "$SEC/clash-api.secret")|" \
  -e "s|__VLESS_UUID__|$(tr -d '\n' < "$SEC/vless-uuid")|" \
  -e "s|__REALITY_PUB__|$(tr -d '\n' < "$SEC/reality.pub")|" \
  -e "s|__REALITY_SHORTID__|$(tr -d '\n' < "$SEC/reality-shortid")|" \
  "$TPL" > "$OUT"
if grep -q '__' "$OUT"; then echo "unrendered placeholder left in $OUT" >&2; exit 1; fi
sing-box check -c "$OUT"
echo "rendered and validated $OUT"

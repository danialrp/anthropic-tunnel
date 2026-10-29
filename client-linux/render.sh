#!/bin/bash
# Render client-linux/sing-box/config.json from the template + private/secrets/.
# Run where private/secrets/ is available. Use --vless-only when no Linux WireGuard
# peer is deployed; this needs no WireGuard credentials.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEC="$ROOT/private/secrets"
OUT="$ROOT/client-linux/sing-box/config.json"
MODE="${1:-dual}"
case "$MODE" in
  dual|--vless-only) ;;
  *) echo "usage: $0 [--vless-only]" >&2; exit 2 ;;
esac
FILES="clash-api.secret server.env vless-uuid reality.pub reality-shortid"
if [ "$MODE" = dual ]; then FILES="$FILES wg-linux.key wg-server.pub wg-psk.key"; fi
for f in $FILES; do
  [ -s "$SEC/$f" ] || { echo "missing $SEC/$f" >&2; exit 1; }
done
# shellcheck disable=SC1090
. "$SEC/server.env"
umask 077
SERVER_IP="$SERVER_IP" python3 - "$ROOT" "$MODE" <<'PY'
import json, os, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
config = json.loads((root / "client-linux/sing-box/config.template.json").read_text())
names = {
    "__CLASH_SECRET__": "clash-api.secret",
    "__VLESS_UUID__": "vless-uuid",
    "__REALITY_PUB__": "reality.pub",
    "__REALITY_SHORTID__": "reality-shortid",
}
if sys.argv[2] == "--vless-only":
    config.pop("endpoints", None)
    selector = next(o for o in config["outbounds"] if o["tag"] == "anthropic")
    selector["outbounds"] = ["vless-out"]
    selector["default"] = "vless-out"
else:
    names.update({"__WG_LINUX_KEY__": "wg-linux.key",
                  "__WG_SERVER_PUB__": "wg-server.pub",
                  "__WG_PSK__": "wg-psk.key"})
values = {key: (root / "private" / "secrets" / name).read_text().strip()
          for key, name in names.items()}
values["__SERVER_IP__"] = os.environ["SERVER_IP"]

def render(value):
    if isinstance(value, dict):
        return {key: render(item) for key, item in value.items()}
    if isinstance(value, list):
        return [render(item) for item in value]
    if isinstance(value, str) and re.fullmatch(r"__[A-Z_]+__", value):
        if value not in values:
            raise SystemExit("Unrendered configuration placeholder")
        return values[value]
    return value

config = render(config)
# Per-machine options are kept outside the shared template. On an IPv4-only
# uplink, a synthetic IPv6 TUN address can make applications choose unusable
# IPv6 connections that fail after their TCP handshake instead of falling back.
options_file = root / "private/secrets/linux-options.json"
if options_file.exists():
    options = json.loads(options_file.read_text())
    if not isinstance(options, dict) or set(options) - {"ipv4_only"}:
        raise SystemExit("Unknown Linux client option")
    if "ipv4_only" in options and not isinstance(options["ipv4_only"], bool):
        raise SystemExit("ipv4_only must be a boolean")
    if options.get("ipv4_only"):
        for inbound in config["inbounds"]:
            if inbound["type"] == "tun":
                inbound["address"] = [address for address in inbound["address"] if ":" not in address]
# Optional imported profiles stay in private/secrets/ so re-rendering preserves them
# without putting their credentials in the tracked template.
extra_file = root / "private/secrets/extra-outbounds.json"
if extra_file.exists():
    extras = json.loads(extra_file.read_text())
    if not isinstance(extras, list):
        raise SystemExit("extra-outbounds.json must contain an array")
    tags = {item["tag"] for item in config["outbounds"] + config.get("endpoints", [])}
    selector = next(item for item in config["outbounds"] if item["tag"] == "anthropic")
    for item in extras:
        if not isinstance(item, dict) or item.get("type") not in ("vless", "socks"):
            raise SystemExit("Imported profiles must be VLESS or SOCKS outbounds")
        tag = item.get("tag")
        if not isinstance(tag, str) or not tag or tag in tags:
            raise SystemExit("Imported profile tags must be nonempty and unique")
        if item.get("tls", {}).get("insecure"):
            raise SystemExit("Imported TLS profiles must verify their peer")
        if item["type"] == "socks" and (
            item.get("server") != "127.0.0.1" or not item.get("username") or not item.get("password")
        ):
            raise SystemExit("Imported SOCKS helpers must use authenticated loopback listeners")
        tags.add(tag)
        config["outbounds"].append(item)
        selector["outbounds"].append(tag)

out = root / "client-linux/sing-box/config.json"
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    os.fchmod(f.fileno(), 0o600)
    json.dump(config, f, indent=2)
    f.write("\n")
PY
CHECK_BIN="$ROOT/client-linux/bin/sing-box"
[ -x "$CHECK_BIN" ] || CHECK_BIN=sing-box
"$CHECK_BIN" check -c "$OUT"
echo "rendered and validated $OUT"

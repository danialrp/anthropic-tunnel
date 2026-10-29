#!/bin/bash
# Install the anthropic-tunnel client on Ubuntu. Run with sudo from the repo:
#   sudo bash client-linux/scripts/install.sh
# Idempotent: re-running updates binary, config, scripts, units and restarts.
# Needs: systemd, systemd-resolved (resolvectl), iproute2, python3, curl or wget, and
# client-linux/sing-box/config.json rendered where private/secrets/ lives (render.sh)
# and copied here.
set -eu
. "$(dirname "$0")/common.sh"
need_root
REPO=$(cd "$(dirname "$0")/../.." && pwd)
VERSION="1.14.4"
# sha256 of the official release tarballs, measured 2026-10-29 (spec/08-client-linux.md)
SHA_amd64="699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968"
SHA_arm64="436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26"

command -v resolvectl >/dev/null || { echo "systemd-resolved (resolvectl) is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v ip >/dev/null || { echo "iproute2 (ip) is required" >&2; exit 1; }
command -v nft >/dev/null || { echo "nftables (nft) is required for the leak guard: sudo apt install nftables" >&2; exit 1; }
[ -s "$REPO/client-linux/sing-box/config.json" ] || { echo "rendered config missing: client-linux/sing-box/config.json (render on the Mac, copy here)" >&2; exit 1; }

# sing-box binary: repo-local copy if present, else download the pinned release tarball
SRC_BIN="$REPO/client-linux/bin/sing-box"
if [ ! -x "$SRC_BIN" ]; then
  case "$(uname -m)" in
    x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;;
    *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  TB="sing-box-$VERSION-linux-$ARCH.tar.gz"
  URL="https://github.com/SagerNet/sing-box/releases/download/v$VERSION/$TB"
  TMPD=$(mktemp -d)
  echo "downloading $URL"
  if command -v curl >/dev/null; then curl -fsSL -o "$TMPD/$TB" "$URL"
  elif command -v wget >/dev/null; then wget -q -O "$TMPD/$TB" "$URL"
  else echo "curl or wget is required to download sing-box" >&2; exit 1; fi
  WANT=$(eval "echo \$SHA_$ARCH")
  GOT=$(sha256sum "$TMPD/$TB" | awk '{print $1}')
  [ "$GOT" = "$WANT" ] || { echo "sha256 mismatch for $TB: got $GOT want $WANT" >&2; exit 1; }
  tar -xzf "$TMPD/$TB" -C "$TMPD"
  mkdir -p "$REPO/client-linux/bin"
  install -m 755 "$TMPD/sing-box-$VERSION-linux-$ARCH/sing-box" "$SRC_BIN"
  rm -rf "${TMPD:?}"
fi
"$SRC_BIN" check -c "$REPO/client-linux/sing-box/config.json"

install -d -o root -g root -m 755 "$BASE" "$BIN" "$ETC"
install -d -o root -g root -m 700 "$VAR"
install -o root -g root -m 755 "$SRC_BIN" "$BIN/sing-box"
install -o root -g root -m 600 "$REPO/client-linux/sing-box/config.json" "$ETC/config.json"
for s in common.sh dns-layer.sh guard.sh tunnel-up.sh tunnel-down.sh tunnel-restart.sh status.sh uninstall.sh; do
  install -o root -g root -m 755 "$REPO/client-linux/scripts/$s" "$BIN/$s"
done
install -o root -g root -m 755 "$REPO/shared/guard-ips.sh" "$BIN/guard-ips.sh"
for u in "$UNIT" "$DNS_UNIT" "$GUARD_UNIT" anthropic-tunnel-guard-refresh.service "$GUARD_TIMER"; do
  install -o root -g root -m 644 "$REPO/client-linux/systemd/$u" "$UNIT_DIR/$u"
done
printf 'anthropic-tunnel client %s. Scripts in %s. Docs: spec/08-client-linux.md in the repo.\n' "$VERSION" "$BIN" > "$BASE/README"

# indicator inputs: Clash API secret and server IP, readable by the installing user's group
OWNER="${SUDO_USER:?run with sudo from your own user, not as root}"
python3 - "$ETC" <<'PYTHON'
import json, pathlib, sys
etc = pathlib.Path(sys.argv[1])
config = json.loads((etc / "config.json").read_text())
(etc / "clash-api.secret").write_text(config["experimental"]["clash_api"]["secret"] + "\n")
vless = next((item for item in config["outbounds"] if item.get("tag") == "vless-out"), {})
server = vless.get("server", "")
if not server:
    wg = next((item for item in config.get("endpoints", []) if item.get("type") == "wireguard"), {})
    server = next((peer["address"] for peer in wg.get("peers", []) if peer.get("address")), "")
(etc / "server-ip").write_text(server + "\n")
PYTHON
chown "root:$(id -gn "$OWNER")" "$ETC/clash-api.secret" "$ETC/server-ip"; chmod 640 "$ETC/clash-api.secret" "$ETC/server-ip"

# sudoers: the indicator may run exactly these three scripts without a password
TMP=$(mktemp)
printf '%s ALL=(root) NOPASSWD: %s/tunnel-up.sh, %s/tunnel-down.sh, %s/tunnel-restart.sh\n' \
  "$OWNER" "$BIN" "$BIN" "$BIN" > "$TMP"
visudo -c -f "$TMP" >/dev/null
install -o root -g root -m 440 "$TMP" "$SUDOERS"; rm -f "${TMP:?}"

# NetworkManager (Desktop): never touch our two links
if [ -d /etc/NetworkManager ]; then
  install -d -m 755 /etc/NetworkManager/conf.d
  printf '[keyfile]\nunmanaged-devices=interface-name:%s;interface-name:%s\n' "$DNS_LINK" "$TUN_IF" > "$NM_CONF"
  if systemctl is-active --quiet NetworkManager; then nmcli general reload conf 2>/dev/null || true; fi
fi

systemctl daemon-reload
if python3 - "$ETC/config.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
sys.exit(0 if any(o.get("tag") == "vless-xhttp-80" for o in config["outbounds"]) else 1)
PY
then
  bash "$REPO/client-linux/scripts/install-xhttp.sh"
fi
systemctl enable --quiet "$GUARD_UNIT" "$GUARD_TIMER" "$DNS_UNIT" "$UNIT"
systemctl restart "$GUARD_UNIT"
systemctl restart "$DNS_UNIT"
systemctl restart "$UNIT"
systemctl restart "$GUARD_TIMER"
sleep 3
echo "--- installed. version: $("$BIN/sing-box" version | head -1)"
bash "$BIN/status.sh"

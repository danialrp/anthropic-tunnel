#!/bin/bash
# Smoke-test the Linux client inside a systemd Ubuntu 24.04 container on this
# Mac (Docker Desktop). Not a substitute for a real Ubuntu machine: see
# spec/08-client-linux.md "What the container test cannot show".
#   bash tests/linux-container/run.sh          # build, start, install, test
#   bash tests/linux-container/run.sh clean    # remove the container
# The container uses the VLESS transport (the Mac's WireGuard peer must not be
# shared; the Linux peer needs the server config from server/render.sh).
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
NAME=at-test
if [ "${1:-}" = clean ]; then docker rm -f "$NAME" >/dev/null 2>&1 || true; echo "removed $NAME"; exit 0; fi
[ -s "$REPO/client-linux/sing-box/config.json" ] || { echo "render first: bash client-linux/render.sh" >&2; exit 1; }
docker build -q -t at-ubuntu-test:24.04 "$REPO/tests/linux-container" >/dev/null
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v "$REPO":/repo:ro at-ubuntu-test:24.04 >/dev/null
sleep 6
# Make the container's resolver look like a real Ubuntu host: glibc -> resolved
# stub, upstream DNS per link (as DHCP would set), no global DNS.
docker exec "$NAME" bash -c '
  umount /etc/resolv.conf 2>/dev/null; rm -f /etc/resolv.conf
  printf "nameserver 127.0.0.53\noptions edns0 trust-ad\nsearch .\n" > /etc/resolv.conf
  printf "[Resolve]\n" > /etc/systemd/resolved.conf; systemctl restart systemd-resolved; sleep 1
  resolvectl dns eth0 1.1.1.1; resolvectl default-route eth0 true'
docker exec -e SUDO_USER=tester "$NAME" bash /repo/client-linux/scripts/install.sh
docker exec "$NAME" bash -c '
  S=$(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)
  curl -s -X PUT -H "Authorization: Bearer $S" -d "{\"name\":\"vless-out\"}" http://127.0.0.1:9090/proxies/anthropic -o /dev/null
  echo "--- api via tunnel (expect 401, fake remote_ip):"
  curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code} remote_ip=%{remote_ip}\n" https://api.anthropic.com/v1/models
  echo "--- github direct (expect 200, real IP):"
  curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code} remote_ip=%{remote_ip}\n" https://github.com
  echo "--- kill switch: stop daemon (expect: resolve fails, github still 200)"
  systemctl stop anthropic-tunnel; sleep 1
  resolvectl query claude.ai 2>&1 | head -1
  curl -s --max-time 8 -o /dev/null -w "api: HTTP %{http_code} %{errormsg}\n" https://api.anthropic.com/v1/models
  curl -s --max-time 8 -o /dev/null -w "github: HTTP %{http_code}\n" https://github.com
  systemctl start anthropic-tunnel; sleep 3
  echo "--- back (expect 401):"; curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code}\n" https://api.anthropic.com/v1/models'
echo "container $NAME left running for inspection: docker exec -it $NAME bash ; remove with: $0 clean"

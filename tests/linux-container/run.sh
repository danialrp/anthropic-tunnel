#!/bin/bash
# Smoke-test the Linux client inside a systemd Ubuntu 24.04 container on any
# machine with Docker. Not a substitute for a real Ubuntu machine: see
# spec/08-client-linux.md "What the container test cannot show".
#   bash tests/linux-container/run.sh          # build, start, install, test
#   bash tests/linux-container/run.sh stop     # stop the container (kept for inspection)
# The container uses the VLESS transport (render with --vless-only) unless the
# Linux WireGuard peer is deployed on the server.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
NAME=at-test
if [ "${1:-}" = stop ]; then docker stop "$NAME" >/dev/null 2>&1 || true; echo "stopped $NAME"; exit 0; fi
[ -s "$REPO/client-linux/sing-box/config.json" ] || { echo "render first: bash client-linux/render.sh --vless-only" >&2; exit 1; }
docker ps -a --format '{{.Names}}' | grep -qx "$NAME" && { echo "container $NAME exists: remove it first (docker rm -f $NAME)" >&2; exit 1; }
docker build -q -t at-ubuntu-test:24.04 "$REPO/tests/linux-container" >/dev/null
docker run -d --name "$NAME" --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw -v "$REPO":/repo:ro at-ubuntu-test:24.04 >/dev/null
sleep 6
# Make the container's resolver look like a real Ubuntu host: glibc -> resolved
# stub, upstream DNS per link (as DHCP would set), no global DNS.
docker exec "$NAME" bash -c '
  umount /etc/resolv.conf 2>/dev/null
  printf "nameserver 127.0.0.53\noptions edns0 trust-ad\nsearch .\n" > /etc/resolv.conf
  printf "[Resolve]\n" > /etc/systemd/resolved.conf; systemctl restart systemd-resolved; sleep 1
  resolvectl dns eth0 1.1.1.1; resolvectl default-route eth0 true'
docker exec -e SUDO_USER=tester "$NAME" bash /repo/client-linux/scripts/install.sh
docker exec "$NAME" bash -c '
  B=/usr/local/anthropic-tunnel/bin
  c() { curl -sk --max-time 8 -o /dev/null -w "HTTP %{http_code} %{errormsg} remote_ip=%{remote_ip}" "$@"; echo; }
  S=$(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)
  curl -s -X PUT -H "Authorization: Bearer $S" -d "{\"name\":\"vless-out\"}" http://127.0.0.1:9090/proxies/anthropic -o /dev/null
  $B/guard.sh refresh
  echo "--- api via tunnel (expect 401, fake remote_ip):"; c https://api.anthropic.com/v1/models
  echo "--- api by real IP with the tunnel up (expect 401, into the TUN):"
  c --resolve api.anthropic.com:443:160.79.104.10 https://api.anthropic.com/v1/models
  echo "--- github direct (expect 200, real IP):"; c https://github.com
  echo "--- route bypass like another VPN: Anthropic range to the physical link (expect instant refusal, github 200)"
  ip rule add pref 100 to 160.79.104.0/21 lookup main
  c --resolve api.anthropic.com:443:160.79.104.10 https://api.anthropic.com/v1/models
  c https://github.com
  ip rule del pref 100
  echo "--- daemon stopped (expect: name fails, real IP refused, github 200)"
  systemctl stop anthropic-tunnel; resolvectl flush-caches; sleep 1
  resolvectl query claude.ai 2>&1 | head -1
  c --resolve api.anthropic.com:443:160.79.104.10 https://api.anthropic.com/v1/models
  c https://github.com
  systemctl start anthropic-tunnel; sleep 3
  echo "--- back (expect 401):"; c https://api.anthropic.com/v1/models
  echo "--- tunnel-down lifts the guard (grey, direct on purpose), tunnel-up restores it"
  $B/tunnel-down.sh >/dev/null; nft list tables | grep -c anthropic_guard | sed "s/^/guard tables while down: /"
  $B/tunnel-up.sh >/dev/null; sleep 3; nft list tables | grep -c anthropic_guard | sed "s/^/guard tables after up: /"
  bash $B/status.sh'
echo "container $NAME left running for inspection: docker exec -it $NAME bash ; stop with: $0 stop"

#!/bin/bash
# Full leak test for the macOS client: DNS, live connections, the whole
# sing-box log, the address Anthropic sees, every path around the tunnel
# (physical interface, other utuns, IPv6, UDP), proxies and other VPNs, guard
# health, and normal use. Read-only, no sudo, changes nothing.
#   bash tests/leak-test-macos.sh
# Every probe that would go around the tunnel targets an address the leak
# guard must refuse, so the test itself cannot leak.
S=$(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)
SRV=$(cat /usr/local/anthropic-tunnel/etc/server-ip)
API=http://127.0.0.1:9090
pass=0; fail=0
ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$*"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
UTUN=$(ifconfig | awk '/^[a-z0-9]+: /{i=$1; sub(":","",i)} $1=="inet" && $2=="172.19.0.1" {print i; exit}')
PHYS=$(netstat -rn -f inet | awk '$1=="default" && $NF !~ /^utun/ {print $NF; exit}')
echo "tunnel utun: $UTUN   physical: $PHYS"
echo

echo "== 1. DNS: every Anthropic name gets a fake IP from the tunnel (system resolver)"
for h in claude.ai api.anthropic.com anthropic.com claude.com claude.app claudeusercontent.com claudemcpcontent.com \
         platform.claude.com downloads.claude.ai a-cdn.anthropic.com statsig.anthropic.com x$RANDOM.claude.ai bridge.claudeusercontent.com; do
  a=$(dscacheutil -q host -a name "$h" | awk '/ip_address/{print $2; exit}')
  case "$a" in 198.1[89].*) ok "$h -> $a" ;; "") ok "$h -> no answer (not resolvable outside the tunnel)" ;; *) bad "$h -> $a (real address from the system resolver)" ;; esac
done
r=$(scutil --dns | awk '/domain *: (anthropic.com|claude.ai|claude.com|claude.app|claudeusercontent.com|claudemcpcontent.com)$/{d=$3} /nameserver\[0\]/{if(d){print d"="$3; d=""}}' | sort -u | tr '\n' ' ')
n=$(echo "$r" | grep -o '=172.19.0.2' | wc -l | tr -d ' ')
[ "$n" -ge 6 ] && ok "scutil --dns: six resolver entries point at 172.19.0.2" || bad "scutil --dns resolver entries: $r"
echo

echo "== 2. Live Anthropic connections: every one goes through the tunnel"
curl -s -H "Authorization: Bearer $S" "$API/connections" | python3 -c "$(cat <<'PY'
import json, re, sys
d = json.load(sys.stdin)
apex = re.compile(r'(^|\.)(anthropic\.com|claude\.ai|claude\.com|claude\.app|claudeusercontent\.com|claudemcpcontent\.com)$')
ant = [c for c in d.get("connections", []) if apex.search((c["metadata"].get("host") or c["metadata"].get("sniffHost") or "").rstrip("."))
       or (c["metadata"].get("destinationIP","")).startswith(("160.79.10","160.79.11"))]
direct = [c for c in ant if "anthropic" not in c.get("chains", [])]
print(f"{'PASS' if not direct else 'FAIL'}  {len(ant)} live Anthropic connections, {len(direct)} outside the tunnel; chains seen: {sorted({tuple(c['chains']) for c in ant})}")
procs = sorted({c["metadata"].get("processPath","").split("/")[-1] or "?" for c in ant})
print(f"INFO  processes with Anthropic connections: {', '.join(procs)[:200]}")
PY
)"
echo

echo "== 3. Log audit: any Anthropic destination ever sent direct (whole sing-box log)"
L=/var/log/anthropic-tunnel/sing-box.log
lines=$(wc -l < "$L" | tr -d ' ')
d=$(grep -E 'outbound/direct\[direct\]: outbound (packet )?connection to' "$L" | grep -cE '(anthropic\.com|claude\.ai|claude\.com|claude\.app|claudeusercontent\.com|claudemcpcontent\.com|160\.79\.1(0[4-9]|1[01])\.|2607:6bc0:|34\.120\.108\.227|34\.36\.57\.103|35\.190\.46\.17)')
t=$(grep -E '(endpoint/wireguard\[wg-out\]|outbound/vless\[vless-out\]): outbound (packet )?connection to' "$L" | grep -cE '(anthropic\.com|claude\.ai|claude\.com|claude\.app|claudeusercontent\.com|claudemcpcontent\.com|160\.79\.)')
[ "$d" -eq 0 ] && ok "$lines log lines: $t Anthropic connections through the tunnel, 0 direct" || bad "$d Anthropic connections went direct"
echo

echo "== 4. Address seen by Anthropic = the server, not this Mac"
seen=$(curl -s --max-time 10 https://claude.ai/cdn-cgi/trace | awk -F= '$1=="ip"{print $2}')
if [ -n "$seen" ]; then [ "$seen" = "$SRV" ] && ok "claude.ai sees the server address" || bad "claude.ai sees a different address than the server"; else info "claude.ai trace endpoint gave no ip line"; fi
mine=$(curl -s --max-time 10 https://api.ipify.org)
[ -n "$mine" ] && [ "$mine" != "$SRV" ] && ok "a non-Anthropic site sees this Mac's own address (split tunnel works)" || info "direct address check inconclusive"
echo

echo "== 5. Guard: Anthropic around the tunnel is refused on every other path"
probe() { # label, curl args...
  local l="$1"; shift
  out=$(curl -s --max-time 5 -o /dev/null -w '%{http_code} %{time_total}' "$@" 2>/dev/null); c=${out%% *}; s=${out##* }
  if [ "$c" = 000 ] && awk -v s="$s" 'BEGIN{exit !(s+0<1)}'; then ok "$l refused after ${s}s"; else bad "$l -> HTTP $c after ${s}s"; fi
}
for ip in 160.79.104.10 160.79.105.1 160.79.111.200 34.36.57.103 34.120.108.227 35.190.46.17 198.18.0.5; do
  probe "TCP 443 to $ip via $PHYS" --interface "$PHYS" -k "https://$ip/"
done
probe "TCP 80 to 160.79.104.10 via $PHYS" --interface "$PHYS" "http://160.79.104.10/"
probe "api.anthropic.com by name via $PHYS (fake IP)" --interface "$PHYS" https://api.anthropic.com/v1/models
for u in $(ifconfig -l | tr ' ' '\n' | grep '^utun' | grep -vx "$UTUN"); do
  probe "TCP 443 to 160.79.104.10 via other interface $u" --interface "$u" -k https://160.79.104.10/
done
if ifconfig "$PHYS" | grep -q 'inet6 [23]'; then
  probe "IPv6 to 2607:6bc0::10 via $PHYS" -6 --interface "$PHYS" -k "https://[2607:6bc0::10]/"
else
  info "no global IPv6 on $PHYS: IPv6 path cannot leave anyway (rule is loaded for 2607:6bc0::/48 and 2001:2::/48)"
fi
# UDP (QUIC): pf "block return" answers with ICMP unreachable, so the send fails or is refused at once
u=$(python3 - "$PHYS" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.IPPROTO_IP, 25, socket.if_nametoindex(sys.argv[1]))   # IP_BOUND_IF
s.settimeout(1.5)
try:
    s.connect(("160.79.104.10", 443)); s.send(b"\x00"*32); s.recv(64); print("answered")
except ConnectionRefusedError: print("refused")
except PermissionError: print("refused")
except OSError as e: print("refused" if e.errno in (13, 61, 65) else f"error {e.errno}")
except socket.timeout: print("timeout")
PY
)
[ "$u" = refused ] && ok "UDP 443 (QUIC) to 160.79.104.10 via $PHYS refused" || bad "UDP 443 via $PHYS: $u"
echo

echo "== 6. Things that could carry traffic above the packet layer"
p=$(scutil --proxy | grep -E '(HTTP|HTTPS|SOCKS|ProxyAutoConfig)Enable : 1' | tr '\n' ' ')
[ -z "$p" ] && ok "no system proxy enabled" || bad "system proxy on: $p"
x=$(systemextensionsctl list 2>/dev/null | grep '\[activated enabled\]' | grep -E 'ransparentProxy|AppProxy|ilterData' | tr '\n' ' ')
[ -z "$x" ] && ok "no enabled transparent-proxy or filter extension" || bad "enabled proxy extension: $x"
v=$(scutil --nc list | grep '(Connected)' | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' ')
[ -z "$v" ] && ok "no other VPN service connected" || info "other VPN connected: $v (guard keeps Anthropic out of it)"
env | grep -qiE '^(https?|all)_proxy=' && bad "proxy variables set in this shell" || ok "no proxy environment variables in this shell"
echo

echo "== 7. Guard health"
read -r g n t gu < /usr/local/anthropic-tunnel/etc/guard-status
age=$(( $(date -u +%s) - $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s) ))
[ "$g" = on ] && [ "$gu" = "$UTUN" ] && [ "$age" -lt 30 ] && ok "guard on, passes only $gu, checked ${age}s ago, $n extra addresses" || bad "guard status: $g $n $t $gu (age ${age}s)"
for l in local.anthropic-tunnel local.anthropic-tunnel.guard local.anthropic-tunnel.guard-refresh; do
  launchctl print "system/$l" >/dev/null 2>&1 && ok "launchd job $l loaded" || bad "launchd job $l not loaded"
done
echo

echo "== 8. Normal use still works"
c=$(curl -s --max-time 15 -o /dev/null -w '%{http_code} %{remote_ip}' https://api.anthropic.com/v1/models)
case "$c" in "401 198.1"*) ok "api.anthropic.com through the tunnel: $c" ;; *) bad "api.anthropic.com: $c" ;; esac
c=$(curl -s --max-time 15 -o /dev/null -w '%{http_code}' https://claude.ai/login)
case "$c" in 2*|3*|403) ok "claude.ai answers through the tunnel (HTTP $c)" ;; *) bad "claude.ai: HTTP $c" ;; esac
c=$(curl -s --max-time 15 -o /dev/null -w '%{http_code}' https://github.com)
[ "$c" = 200 ] && ok "github.com direct: 200" || bad "github.com: $c"
echo
echo "RESULT: $pass passed, $fail failed"

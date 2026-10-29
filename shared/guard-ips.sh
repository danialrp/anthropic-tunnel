#!/bin/bash
# Print the addresses of Anthropic hosts that lie outside Anthropic's own
# ranges (for example cloud load balancers), one per line, resolved THROUGH
# the tunnel by sing-box's local API. Used by the leak guard on every client
# (macOS pf, Linux nftables) to keep its block list current.
#   guard-ips.sh <clash-api-secret-file> [api-base-url]
# Exit 1 when the local API does not answer: the caller keeps its last list.
# A host whose answer contains a CNAME outside the six Anthropic domains is
# skipped: such addresses can be shared with unrelated sites on a CDN.
set -u
SECRET=$(cat "$1" 2>/dev/null) || { echo "cannot read secret $1" >&2; exit 1; }
API=${2:-http://127.0.0.1:9090}
APEX='(^|\.)(anthropic\.com|claude\.ai|claude\.com|claude\.app|claudeusercontent\.com|claudemcpcontent\.com)\.?$'
BASE_HOSTS="anthropic.com www.anthropic.com api.anthropic.com a-api.anthropic.com a-cdn.anthropic.com
s-cdn.anthropic.com assets-proxy.anthropic.com console.anthropic.com docs.anthropic.com mcp-proxy.anthropic.com
claude.ai a.claude.ai assets.claude.ai downloads.claude.ai claude.com www.claude.com platform.claude.com
code.claude.com sso.claude.com support.claude.com claude.app claudeusercontent.com bridge.claudeusercontent.com
claudemcpcontent.com"

q() { curl -s --max-time 4 -H "Authorization: Bearer $SECRET" "$API$1"; }

# the API must answer, otherwise report failure so the old list is kept
q /version | grep -q '"version"' || { echo "local API not reachable" >&2; exit 1; }

# hosts seen in current Anthropic connections (new subdomains are picked up here)
SEEN=$(q /connections | grep -oE '"host":"[^"]*"' | sed 's/"host":"//; s/"$//' | grep -E "$APEX")

for h in $(printf '%s\n%s\n' "$BASE_HOSTS" "$SEEN" | tr ' ' '\n' | grep -v '^$' | sort -u); do
  for t in A AAAA; do
    j=$(q "/dns/query?name=$h&type=$t") || continue
    objs=$(printf '%s' "$j" | grep -oE '\{"TTL":[^}]*\}')
    [ -n "$objs" ] || continue
    skip=no; addrs=""
    while IFS= read -r o; do
      typ=$(printf '%s' "$o" | grep -oE '"type":[0-9]+' | cut -d: -f2)
      dat=$(printf '%s' "$o" | grep -oE '"data":"[^"]*"' | sed 's/"data":"//; s/"$//')
      case "$typ" in
        5) printf '%s' "$dat" | grep -qE "$APEX" || skip=yes ;;
        1|28) addrs="$addrs $dat" ;;
      esac
    done <<< "$objs"
    [ "$skip" = yes ] && continue
    for a in $addrs; do
      case "$a" in
        160.79.10[4-9].*|160.79.11[01].*) ;;          # inside 160.79.104.0/21 (static)
        2607:6bc0:*|2607:6BC0:*) ;;                   # inside 2607:6bc0::/48 (static)
        198.1[89].*|2001:2:*|2001:0002:*) ;;          # fake-IP ranges, never real
        *) echo "$a" ;;
      esac
    done
  done
done | sort -u

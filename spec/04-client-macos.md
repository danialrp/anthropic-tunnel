# 04 — Client (macOS)

## Pieces

| Piece | Runs as | Started by | Purpose |
|---|---|---|---|
| sing-box (TUN) | root | launchd daemon `local.anthropic-tunnel` | routing, DNS, kill switch |
| SwiftBar plugin | user | launchd agent / SwiftBar | indicator and control |

## sing-box config (written 2026-10-28; template `client/sing-box/config.template.json`, rendered by `client/render.sh`)

- `inbounds`: one `tun` (172.19.0.1/30 + a ULA v6), `auto_route`,
  `strict_route`, stack `mixed`. sing-box adds 0.0.0.0/1-style routes via
  utun; the LAN subnet keeps its more specific link route.
- **DNS on macOS (found 2026-10-28):** sing-box 1.14 does not set the Mac's
  system DNS (sing-tun's darwin code only flushes the cache), and queries to
  the LAN router never enter the TUN. So the system
  resolver would still resolve Anthropic names directly. Fix: six per-domain
  resolver files `/etc/resolver/<apex>` containing `nameserver 172.19.0.2`
  (the TUN's DNS address, hijacked into sing-box). Effects: only those six
  domains are affected, every app using the system resolver (Chrome included)
  gets a fake IP, nothing else on the Mac changes, and if sing-box is not
  running those names simply fail to resolve (fail-closed even in the gap).
  Verified with `dscacheutil` and Python `getaddrinfo`. `dig` bypasses
  `/etc/resolver`, so it is not a valid test. Revert: delete the six files.
- `dns.servers`: `fake` (fakeip 198.18.0.0/15, 2001:2::/48), `dns-tunnel`
  (UDP 1.1.1.1 with `detour: anthropic`, i.e. inside the tunnel), `system`
  (`local`, the Mac's normal resolver).
- `dns.rules`: (1) A/AAAA from `tun-in` for the six suffixes → `fake`;
  (2) HTTPS/SVCB for those suffixes → `reject` (no IP hints to apps);
  (3) anything else for those suffixes, which includes sing-box's own lookup
  of the real IP for the WireGuard endpoint, → `dns-tunnel`. Everything else
  → `system`. (First version rejected all non-A/AAAA, which also rejected the
  internal lookup and broke every fake-IP connection; fixed 2026-10-28.)
- `endpoints`: `wg-out` (WireGuard to the server, MTU 1280, allowed_ips
  0.0.0.0/0 and ::/0, keepalive 25 s). Its `domain_resolver` is `dns-tunnel`
  with `ipv4_only`: the real IP of an Anthropic host is looked up through the
  tunnel, so even the DNS query for an Anthropic name never leaves directly.
- `outbounds`: selector `anthropic` = [`wg-out`, `vless-out`], default
  `wg-out`, `interrupt_exist_connections` so a switch takes effect at once;
  `vless-out` = VLESS to the server on TCP 8444, `xtls-rprx-vision`, Reality
  with SNI www.apple.com, uTLS chrome fingerprint, public key + short_id from
  `private/secrets/`; `direct`, `block`. The selector never contains `direct`.
  Switching transport: menu bar → Transport, or
  `PUT /proxies/anthropic {"name":"vless-out"}` on the Clash API. The choice
  persists in cache.db.
- `route.rules`, in order:
  1. `sniff` (TLS SNI / HTTP host), so a connection to a real IP that an app
     resolved by itself (e.g. Chrome's own DoH) is still recognised by domain
  2. DNS → `hijack-dns`
  3. six suffixes → `anthropic`
  4. Anthropic's published IP ranges 160.79.104.0/23, 2607:6bc0::/48 →
     `anthropic` (belt and braces for hard-coded IPs)
  5. private destinations → `direct`
  `final: direct`, `auto_detect_interface: true`,
  `default_domain_resolver: system`.
  There is no path by which an Anthropic domain or IP can reach `direct`.
  If the tunnel is down the connection fails. That is the kill switch.
- `experimental.clash_api` on 127.0.0.1:9090 with a secret from `private/secrets/`;
  `cache_file` under `/Library/Application Support/anthropic-tunnel/` keeps
  fake-IP mappings and the selector choice across restarts.

Known limit (documented, not hidden): a client that uses its own encrypted
DNS and Encrypted Client Hello would show neither a hijackable query nor a
readable SNI. Only the IP-range rule and the leak guard below catch that case.

## Mac environment found on 2026-10-28

- Any macOS that runs sing-box 1.14.4 (Homebrew) and python3 (Homebrew or
  Xcode CLT); the operator's tested build, hardware and local networks are in
  the git-ignored `private/notes.md`.
- No proxy app running; system proxies off. Several VPN apps are installed
  but idle (names in `private/notes.md`).
  If one of them is switched on it takes the default route and DNS; the
  leak guard below then refuses every packet to Anthropic that does not
  leave through our utun. Operational rule in 06.
- Six utun interfaces exist (system/iCloud); sing-box creates its own.
- `sudo` needs a password: every privileged step is run by the operator in the
  terminal pane; the agent prepares the exact command.

## Installed layout (client/scripts/install.sh, written 2026-10-28)

| Path | Content | Owner/mode |
|---|---|---|
| /usr/local/anthropic-tunnel/bin/sing-box | copy of the brew binary (root-owned so the daemon never executes a user-writable file) | root 755 |
| /usr/local/anthropic-tunnel/bin/*.sh | common, tunnel-up, tunnel-down, tunnel-restart, status, uninstall | root 755 |
| /usr/local/anthropic-tunnel/etc/config.json | rendered config (secrets inside) | root 600 |
| /usr/local/anthropic-tunnel/var/ | sing-box working dir, cache.db | root 700 |
| /var/log/anthropic-tunnel/sing-box.log | daemon stdout+stderr | root |
| /Library/LaunchDaemons/local.anthropic-tunnel.plist | RunAtLoad, KeepAlive, ThrottleInterval 5 | root 644 |
| /etc/sudoers.d/anthropic-tunnel | `<user> ALL=(root) NOPASSWD:` the three up/down/restart scripts by absolute path | root 440 |
| /etc/resolver/{six apexes} | `nameserver 172.19.0.2` | root 644 |

No spaces in any path on purpose (sudoers and launchd quoting). Re-running
install.sh updates everything and restarts the daemon. `uninstall.sh` removes
all of the above (brew sing-box stays).

States: `tunnel-up.sh` = daemon loaded + resolver files; `tunnel-down.sh`
(GREY) = daemon unloaded + resolver files removed, Anthropic goes direct on
purpose; `tunnel-restart.sh` = `launchctl kickstart -k`.

## What happens if sing-box itself dies

launchd `KeepAlive` restarts it within seconds. In the gap the TUN is gone,
but the `/etc/resolver` files still point Anthropic names at 172.19.0.2, which
no longer exists, so those names fail to resolve and existing fake IPs
(198.18.0.0/15) have no route. The leak guard (below) also refuses any
packet to an Anthropic address on any other interface, which covers apps
that resolve names themselves.

## Leak guard (pf, since 2026-10-29)

Packet-level layer that holds even when sing-box is down, when another VPN
owns the routes, or when an app resolves names itself and connects to a real
address. It blocks every outgoing packet to Anthropic addresses unless it
leaves through our own utun.

- **Rules** live in the anchor `com.apple/250.anthropic-tunnel`, directly
  under Apple's `anchor "com.apple/*"` hook in `/etc/pf.conf`, so
  `/etc/pf.conf` is never edited. Rendered by `client/scripts/guard.sh`:
  ```
  table <anthropic_static> persist { 160.79.104.0/21, 198.18.0.0/15, 2607:6bc0::/48, 2001:2::/48 }
  table <anthropic_dynamic> persist file "/usr/local/anthropic-tunnel/var/guard-dynamic.txt"
  pass out quick on <our utun> to <anthropic_static>
  pass out quick on <our utun> to <anthropic_dynamic>
  block return out quick to <anthropic_static>
  block return out quick to <anthropic_dynamic>
  ```
  The two pass lines exist only while our utun (the interface holding
  172.19.0.1) exists; without it everything to those addresses is refused.
  `block return` makes connections fail at once instead of timing out.
- **Static addresses**: Anthropic's own range 160.79.104.0/21 and
  2607:6bc0::/48 (most hosts, including claude.ai and api.anthropic.com,
  resolve to 160.79.104.10 as of 2026-10-29), and sing-box's fake-IP ranges.
- **Dynamic addresses**: hosts outside that range (Google Cloud load
  balancers for assets.claude.ai, downloads.claude.ai, a-cdn.anthropic.com on
  2026-10-29). `client/scripts/guard-ips.sh` resolves a fixed host list plus every
  Anthropic host seen in current connections through sing-box's local API
  (`/dns/query`, which answers through the tunnel), and skips any host whose
  answer has a CNAME outside the six Anthropic domains, because such
  addresses can be shared with unrelated sites on a CDN (s-cdn.anthropic.com,
  status.claude.com). Those hosts stay covered by domain routing, not by the
  guard. If the API does not answer, the last list is kept.
- **Jobs**: `local.anthropic-tunnel.guard` runs `guard.sh apply` every 5 s:
  enables pf if it is off (`pfctl -E`, token kept in var/ and released on
  `down`), reloads Apple's ruleset if the `com.apple/*` hook disappeared
  (some network changes flush it), and reloads the anchor whenever the utun
  name changed or the anchor is empty. `local.anthropic-tunnel.guard-refresh`
  runs `guard.sh refresh` every 5 min. Log: `/var/log/anthropic-tunnel/guard.log`.
  Status for the indicator: `/usr/local/anthropic-tunnel/etc/guard-status`
  (`on|off|error <count> <UTC time> <utun>`).
- **Grey state**: `tunnel-down.sh` lifts the guard (Anthropic goes direct on
  purpose); `tunnel-up.sh` restores it. `tunnel-restart.sh` re-points the
  guard right after the restart; after a crash restart by launchd the guard
  follows within 5 s, and in between traffic is refused, not leaked.
- **Install**: `sudo bash client/scripts/guard-install.sh` (also run at the
  end of install.sh). It never restarts the tunnel. It runs a self-test:
  Anthropic must answer through the tunnel (otherwise it removes the guard
  again by itself), and a fake-IP address forced onto the physical interface
  must be refused in well under a second (a guarded address that routes
  nowhere, so the probe cannot reach Anthropic even if the guard failed).
- **Revert**: `sudo bash /usr/local/anthropic-tunnel/bin/guard-off.sh`
  (unloads both jobs, flushes the anchor, releases the pf reference).

What pf cannot stop: system HTTP/SOCKS proxies and NetworkExtension
transparent or app proxies, which take connections above the IP layer. The
indicator detects them (`scutil --proxy`, `systemextensionsctl list`) and
turns red with `PROXY` (spec/05).

## launchd daemon

`client/launchd/local.anthropic-tunnel.plist` (lint-checked). Runs
`/usr/local/anthropic-tunnel/bin/sing-box run -c …/etc/config.json -D …/var`
as root at boot, before login, restarted on exit after 5 s.

## macOS permission

First run of a TUN needs user approval (utun creation as root works without a
Network Extension, but macOS may prompt for local network / full disk for the
process). The operator does the click; the agent waits.

## Manual control

See "Installed layout" above. All three control scripts are runnable by
the installing user through sudo without a password (sudoers entry validated with
`visudo -c`).

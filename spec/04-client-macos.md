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
readable SNI. Only the IP-range rule and the pf second layer catch that case.

## Mac environment found on 2026-10-28

- Any macOS that runs sing-box 1.14.4 (Homebrew) and python3 (Homebrew or
  Xcode CLT); the operator's tested build, hardware and local networks are in
  the git-ignored `private/notes.md`.
- No proxy app running; system proxies off. Several VPN apps are installed
  but idle (names in `private/notes.md`).
  If one of them is switched on it takes the default route and DNS; then
  Rule 0 depends on the pf layer. Recorded as an operational rule in 06.
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
(198.18.0.0/15) have no route. The gap is therefore fail-closed without pf.
The pf anchor remains an optional third layer for the case where another VPN
app takes over DNS and routing; it is not part of the first install.

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

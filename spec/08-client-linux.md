# 08 — Client (Ubuntu Linux)

**Status (2026-10-29):** written and tested in a systemd Ubuntu 24.04 container
on the Mac (Docker Desktop, arm64). Not yet run on a real Ubuntu machine; the
open points are listed at the end and in `spec/todo.md`. Same rules, same
behaviour as the macOS client (spec/04): all Anthropic traffic through the
tunnel, fail-closed, nothing else touched.

## Pieces

| Piece | Runs as | Started by | Purpose |
|---|---|---|---|
| sing-box 1.14.4 (TUN + DNS listener) | root | systemd `anthropic-tunnel.service` | routing, DNS, kill switch |
| DNS layer | root (oneshot) | systemd `anthropic-tunnel-dns.service` | the six apexes resolve only through sing-box, even when it is down |
| Indicator | user | Argos (GNOME Shell extension) | same plugin file as macOS, `menubar/anthropic-tunnel.5s.py` |

Files: `client-linux/` (config template, render.sh, systemd units,
scripts), `menubar/install-linux.sh`, `tests/linux-container/`. The
step-by-step runbook for the agent on the Ubuntu machine, including the
real-machine test matrix L1–L12, is `client-linux/README.md`.

## sing-box config (`client-linux/sing-box/config.template.json`)

Identical to the macOS template except:

- TUN `interface_name: anthropic-tun0`, `dns_mode: disabled`. With the
  default (`hijack`) sing-box 1.14 on Linux runs `resolvectl domain <tun> ~.`
  and makes its TUN the DNS route for every domain (research 2026-10-29,
  sing-tun `tun_linux.go`). That is not the six-suffix design, and the setting
  vanishes with the TUN, so it is disabled and our own layer is used instead.
- A second inbound: `direct` on `172.19.0.9:5553` (UDP+TCP; the address of
  the dummy link created by the DNS layer) with `override_address
  172.19.0.2:53`. The first route rule sends that inbound to `hijack-dns`.
  This is the DNS server that systemd-resolved talks to. The daemon unit
  `Requires=` the DNS unit so the address exists before sing-box binds it.
- DNS rule 1 (fake-IP for the six suffixes) matches `inbound: [tun-in, dns-in]`.
- WireGuard: own key (`private/secrets/wg-linux.key`), own address `10.66.66.3/32`,
  own peer on the server (`server/sing-box/config.template.json`). The Mac's
  peer is never shared: two clients on one WireGuard peer would steal each
  other's session (endpoint roaming) and cut the Mac's line (rule 12).
- VLESS: same UUID as the Mac (VLESS users are multi-session).
- Cache: `/usr/local/anthropic-tunnel/var/cache.db` (same path as macOS).

Observed in the container with `dns_mode: disabled`: sing-box still installs
policy rules (`ip rule`, priorities 9000–9010, table 2022) and port-53 traffic
to any address **does** enter the TUN (`ip route get 1.1.1.1 dport 53` →
`anthropic-tun0`). So the `port 53 → hijack-dns` route rule still catches apps
that use their own plain DNS, as on macOS. systemd-resolved's own upstream
queries also go through sing-box; for non-Anthropic names sing-box's `local`
server answers them. `local` on Linux resolves "through systemd-resolved's
DBus interface when available" (sing-box docs): it asks resolved for the
per-link upstream servers and queries them directly, bound to the physical
interface, so there is no loop through the stub. Requirement that follows:
**the upstream DNS must be configured per link (DHCP/NetworkManager/networkd
do this), not only as a global `DNS=` in resolved.conf**; with no per-link
server sing-box's `local` fell back to Go's default `[::1]:53` and every
non-Anthropic lookup failed (seen in the container before the per-link server
was set).

## DNS layer (`client-linux/scripts/dns-layer.sh`, unit `anthropic-tunnel-dns.service`)

macOS has `/etc/resolver/<domain>` files. Linux (Ubuntu Desktop and Server
both use systemd-resolved as the stub resolver) has per-link *routing
domains*: a name that matches `~claude.ai` on a link goes only to that link's
DNS servers and never to the default ones; resolved does not fall back on
failure ("the unicast DNS query fails", resolved man page; confirmed in the
container: `Lookup failed due to system error: Connection refused`).

Two resolved facts shaped the design (research + container test, 2026-10-29):

1. A link's DNS server is reached with the socket bound to that link
   (`SO_BINDTODEVICE`), **except loopback addresses**, which always go via
   `lo`. So the server cannot be the TUN's 172.19.0.2 on a dummy link (the
   packet would be dropped on the dummy). A loopback server works for the
   six domains, but resolved then also treats it as usable for every other
   name (it reports it with ifindex 1 and, in the container, sent
   non-Anthropic queries to it as well). The clean answer is the dummy
   link's **own** address: the kernel delivers a packet to a local address
   even when the socket is bound to that link, and resolved keeps the server
   strictly per-link. Hence `172.19.0.9/32` on `anthropic-dns0` and the
   sing-box `direct` inbound on `172.19.0.9:5553`. Verified: three
   non-Anthropic lookups caused zero connections on `dns-in`; a `claude.ai`
   lookup caused two (A and AAAA).
2. Settings attached to the TUN link itself die with the TUN (not
   fail-closed). Hence a persistent dummy link that exists whether or not
   sing-box runs.

So `dns-layer.sh up` does: `ip link add anthropic-dns0 type dummy`, give it
`172.19.0.9/32` (resolved ignores a link without an address, and sing-box
listens there), `resolvectl dns anthropic-dns0 172.19.0.9:5553`, `resolvectl domain anthropic-dns0 ~anthropic.com
~claude.ai ~claude.com ~claude.app ~claudeusercontent.com ~claudemcpcontent.com`,
`resolvectl default-route anthropic-dns0 false`, flush caches. `down` reverts
and deletes the link. The unit is `oneshot` + `RemainAfterExit`, enabled at
boot, ordered before the daemon.

Verified in the container: routing domains applied; `resolvectl query
claude.ai` → fake IP through sing-box; daemon stopped → the query fails,
`curl https://api.anthropic.com` → "Could not resolve host", github.com still
200, TUN gone; daemon back → works; the link configuration survives
`systemctl restart systemd-resolved`; a non-Anthropic name never reaches the
listener (`resolvectl dns` shows it only under `anthropic-dns0`, nothing under
Global). resolved caches answers up to their TTL (fake-IP answers carry 600
s): right after sing-box stops, a cached name still returns its fake IP, which
has no route (198.18.0.0/15 is unroutable), so the connection fails; after
the TTL the name fails to resolve. Fail-closed either way, as on macOS where
the system cache behaves the same.

Install also writes `/etc/NetworkManager/conf.d/anthropic-tunnel.conf`
(`unmanaged-devices` for `anthropic-dns0` and `anthropic-tun0`) when
NetworkManager is present, so the Desktop network manager never reconfigures
the two links. Not yet verified on a real Desktop (todo).

## Installed layout (`client-linux/scripts/install.sh`)

| Path | Content | Owner/mode |
|---|---|---|
| /usr/local/anthropic-tunnel/bin/sing-box | from the official release tarball, sha256-pinned in install.sh | root 755 |
| /usr/local/anthropic-tunnel/bin/*.sh | common, dns-layer, tunnel-up, tunnel-down, tunnel-restart, status, uninstall | root 755 |
| /usr/local/anthropic-tunnel/etc/config.json | rendered config (secrets inside) | root 600 |
| /usr/local/anthropic-tunnel/etc/clash-api.secret | for the indicator | root:<user> 640 |
| anthropic-dns0 (dummy link, 172.19.0.9/32) | DNS layer, created by the unit at boot | |
| /usr/local/anthropic-tunnel/var/ | sing-box working dir, cache.db | root 700 |
| /etc/systemd/system/anthropic-tunnel.service, anthropic-tunnel-dns.service | units, enabled | root 644 |
| /etc/sudoers.d/anthropic-tunnel | `<user> ALL=(root) NOPASSWD:` the three up/down/restart scripts | root 440 |
| /etc/NetworkManager/conf.d/anthropic-tunnel.conf | unmanaged-devices (only if NetworkManager exists) | root 644 |
| journal `journalctl -u anthropic-tunnel` | daemon log (no log file) | |

sing-box is taken from the release tarball, not the `.deb`: the package
installs its own `sing-box.service`, a `sing-box` user, polkit and D-Bus
policies for resolved, and may start with its default config. The tarball is
one binary, copied root-owned like on macOS. Pinned sha256 (measured
2026-10-29 from github.com/SagerNet/sing-box/releases/tag/v1.14.4; the
release publishes no checksum file):

```
sing-box-1.14.4-linux-amd64.tar.gz  699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968
sing-box-1.14.4-linux-arm64.tar.gz  436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26
```

`install.sh` downloads the tarball for the machine's arch into
`client-linux/bin/` (git-ignored) unless a binary is already there, verifies
the hash, checks the config, installs everything, enables and (re)starts both
units. Re-running updates in place. `uninstall.sh` removes all of the above
(verified in the container: no units, link, rules or files left).

Requirements on the Ubuntu box: systemd, systemd-resolved (default on Desktop
and Server), iproute2, python3 (default), curl or wget (Server has curl;
Desktop may not), sudo for the first user (default). The rendered config is
produced on the Mac (`bash client-linux/render.sh`, needs `private/secrets/`) and
copied to the Linux clone as `client-linux/sing-box/config.json`.

States: `tunnel-up.sh` = both units enabled and started; `tunnel-down.sh`
(GREY) = both disabled and stopped, dummy link removed, Anthropic goes direct
on purpose; `tunnel-restart.sh` = `systemctl restart`. `systemctl stop
anthropic-tunnel` by hand leaves the unit enabled: the indicator shows grey
"?" (daemon enabled but not running) and the DNS layer keeps Anthropic names
failing, so that is fail-closed too.

## What happens if sing-box dies

`Restart=always`, `RestartSec=2`. In the gap the TUN and its policy rules are
gone, the dummy link and its routing domains remain, `127.0.0.1:5553` is
closed, so the six domains fail to resolve and existing fake IPs
(198.18.0.0/15) have no route. Verified: `kill -9` → new PID within 4 s,
`NRestarts=1`, traffic back.

## Indicator (Argos)

Same plugin file as macOS. On Linux (`sys.platform`) it uses `systemctl
is-enabled/is-active`, `ip`, `resolvectl`, `journalctl`, `notify-send`,
`wl-copy`/`xclip` (or writes `~/anthropic-tunnel-diagnostics.txt`), and
emits BitBar-format output: single dark-theme colour instead of SwiftBar's
light,dark pair, no `sfimage`/`sfcolor`/`disabled`/`checked`/`font`
parameters, the active transport marked with ✓ in its label. Secret read from
`/usr/local/anthropic-tunnel/etc/clash-api.secret`. The macOS branch of the
file is untouched in behaviour: its SwiftBar output was diffed before and
after the change (identical apart from volatile numbers) and the installed
copy re-checked. `menubar/install-linux.sh`
copies it to `~/.config/argos/anthropic-tunnel.5s.py` with a
`/usr/bin/python3` interpreter line and prints how to install Argos (from its
git master, which supports GNOME 45–51; the extensions.gnome.org listing is
stale). Verified in the container: output format, states green/grey, the
transport, diag and flush actions. Not verified: rendering inside GNOME
Shell itself (no GNOME in the container; todo).

## Container test on the Mac (`tests/linux-container/`)

`bash tests/linux-container/run.sh` builds a systemd Ubuntu 24.04 image,
starts it privileged with the repo mounted read-only, gives it a resolver
setup like a real host (glibc → resolved stub, upstream DNS per link), runs
`install.sh`, switches the selector to VLESS and runs the kill-switch checks.
Results 2026-10-29 (arm64 image, Docker Desktop):

| Check | Result |
|---|---|
| install.sh (binary from client-linux/bin, config check, units, sudoers, secret file) | PASS |
| DNS layer: 6 routing domains on anthropic-dns0 → 172.19.0.9:5553; non-Anthropic names never reach the listener | PASS |
| `resolvectl query claude.ai` / `getent` → 198.18.0.x | PASS |
| TUN default route (table 2022, rules 9000–9010) | PASS |
| api.anthropic.com → 401, remote_ip fake, chain vless-out | PASS |
| github.com direct, real IP | PASS |
| Daemon stopped: claude.ai "Connection refused", curl "Could not resolve host", github 200, TUN gone | PASS |
| Daemon started: traffic back | PASS |
| kill -9: restarted by systemd, traffic back | PASS |
| `systemctl restart systemd-resolved`: routing domains survive | PASS |
| tunnel-down.sh: units disabled, link gone, claude.ai resolves normally; tunnel-up.sh: back, api 401 | PASS |
| Container restart: both units start on their own, DNS layer and TUN up | PASS |
| DNS unit stopped by hand, then `systemctl start anthropic-tunnel`: Requires= brings the DNS layer back first | PASS |
| uninstall.sh: no units, link, rules, sudoers, files left; DNS normal | PASS |
| Indicator plugin (Linux branch) output and actions | PASS |
| WireGuard transport | not testable until the Linux peer is deployed on the server |

### What the container test cannot show

- Real boot ordering with NetworkManager/netplan, DHCP-provided per-link DNS,
  and whether NetworkManager leaves the two links alone.
- Docker replaces `/etc/resolv.conf` on every container start, so the boot
  test ran with the resolver fixed up by hand afterwards.
- Behaviour of resolved's cache and TTLs on a long-running desktop.
- The Argos extension inside GNOME Shell.
- The "direct" leak check: the container sits behind the Mac's own tunnel,
  so a leaked Anthropic packet would still be caught by the Mac. Leaks were
  therefore judged from the container's sing-box log and resolved behaviour,
  not from an outside observer.
- WireGuard from the Linux client (needs the server peer).

## Open points

See `spec/todo.md`: deploy the Linux WireGuard peer on the server (needs
The operator's go), first run on a real Ubuntu machine (Desktop with NetworkManager
and, if used, Server with networkd), Argos in GNOME, optional
`auto_redirect` (sing-box recommends it on Linux; it adds nftables rules and
redirects port 53 by itself; evaluate after the real-machine run).

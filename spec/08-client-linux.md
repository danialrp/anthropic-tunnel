# 08 — Client (Ubuntu Linux)

**Status (2026-10-29):** container tests passed on Ubuntu 24.04 arm64; the
VLESS client is now installed and running on a real Ubuntu workstation.
TUN/DNS startup and an API request passed; real-host failure and reboot tests
remain open in `spec/todo.md`. Same rules, same
behaviour as the macOS client (spec/04): all Anthropic traffic through the
tunnel, fail-closed, nothing else touched.

## Real-machine preparation (2026-10-29)

A Linux workstation has been prepared using the existing project VLESS/Reality
listener on TCP 8444. The pinned amd64 archive passed SHA256 verification,
`sing-box check` passed, and a temporary unprivileged SOCKS probe reached
`https://api.anthropic.com/v1/models` through VLESS and returned HTTP 401.
The probe had only a VLESS outbound and was removed afterwards; it did not
change system routing. The user then installed the client with interactive sudo. Initial startup
failed because another VPN TUN had been enabled again and owned routing table
2022. After the user disabled that TUN, restarting only
`anthropic-tunnel.service` succeeded. Observed: daemon active/running,
`NRestarts=0` after restart, all six DNS routing domains, TUN up, `claude.ai`
resolved to a fake IP, and the API returned HTTP 401 with `vless-out` in the
daemon log. Full real-host fail-closed and reboot tests remain pending.
Environment-specific details are in `private/notes.md`.

The Linux defaults now use `172.30.250.1/30` for the TUN,
`172.30.250.2` for its internal DNS target and `172.30.250.9/32` for the
persistent DNS link (listener port 5553). The previous `172.19.0.1` conflicts
with a Docker bridge on this workstation. These new addresses were checked
against its existing interfaces; check for overlap again on other machines.
The historical container results below used the original addresses.
The macOS addresses are unchanged.

For a VLESS-only installation, put `server.env` (`SERVER_IP=...`),
`vless-uuid`, `reality.pub`, `reality-shortid` and `clash-api.secret` in
`private/secrets/`, then run:

```bash
bash client-linux/render.sh --vless-only
sudo bash client-linux/scripts/install.sh
bash /usr/local/anthropic-tunnel/bin/status.sh
```

The renderer uses the cached `client-linux/bin/sing-box` when available,
otherwise `sing-box` on PATH. It requires Python 3, writes the generated
config with mode 600 and checks it before reporting success. This mode omits
WireGuard entirely and starts with `vless-out` in the selector, so an undeployed
Linux peer cannot be selected accidentally. Optional imported profiles are
appended as described below. The default invocation still
renders both transports and requires all WireGuard secrets. Do not rerender a
VLESS-only setup without the flag. The installer starts the services immediately.
The cached binary must come from the pinned release; the installer trusts an
existing executable in `client-linux/bin/`.

Rollback after installation: `sudo bash client-linux/scripts/uninstall.sh`.
This removes the tunnel and restores ordinary DNS/direct access; it is not a
fail-closed pause. To stop only the daemon while retaining its DNS block, use
`sudo systemctl stop anthropic-tunnel` and leave the DNS unit running.

## Imported server profiles (2026-10-29)

`private/secrets/extra-outbounds.json` is an optional array of additional VLESS
outbounds and authenticated loopback SOCKS helpers. Both render modes append
these profiles to the `anthropic` selector without changing its default,
DNS rules, routing rules or direct outbound. This keeps imported credentials
out of tracked files and preserves them when re-rendering. Duplicate/reserved
tags, direct outbounds, TLS `insecure: true` and unauthenticated/non-loopback
SOCKS helpers are rejected before replacing the generated config.

The current import contains the project's existing VLESS profile plus five
server profiles. Private inventory, credentials and probe results are in
`private/notes.md` and `private/secrets/`; no server configuration was changed. A
WireGuard profile is not added until this Linux machine has its own server
peer. The Mac peer must not be reused.

The two imported TLS profiles use SPKI SHA256 pins derived from certificates
retrieved over authenticated SSH. Pin verification replaces ordinary CA/name/
expiry validation for these profiles; it never accepts an arbitrary peer.
One profile's CA certificate is expired and the other is self-signed. Wrong-pin
probing confirmed rejection (`unrecognized remote public key`). A changed
server public key requires updating the pin from a trusted source. See the
[official TLS fields](https://sing-box.sagernet.org/configuration/shared/tls/#certificate_public_key_sha256).
The imported origin WebSocket/XHTTP routes have no outer TLS; destination
HTTPS remains end-to-end, but the proxy metadata and any non-TLS payload are
not encrypted on the client-to-origin hop.

### XHTTP helper

The pinned sing-box build does not support XHTTP natively (see the
[official transport list](https://sing-box.sagernet.org/configuration/shared/v2ray-transport/)).
A dedicated Xray process provides only that transport, behind authenticated
SOCKS at `127.0.0.1:19080`. It has no TUN, route changes or direct fallback.
Its outbound connects to the imported server's existing XHTTP reverse proxy.
`private/secrets/xhttp-client.json` supplies its credentials. The Linux binary is
cached at `client-linux/bin/xray`, copied over authenticated SSH from the
existing server, with SHA256 checked locally against the remote binary:

- Xray 26.3.27, revision d2758a0, linux/amd64.
- SHA256: `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`.
- This optional helper pin covers amd64 only; a separate verified binary/pin
  is required for an arm64 XHTTP installation.

`install-xhttp.sh` installs the binary, root-only `etc/xhttp.json`, and
`anthropic-tunnel-xhttp.service`. systemd supplies the config through
`LoadCredential`; Xray runs as a dynamic unprivileged user. A project-only
`anthropic-tunnel.service.d/xhttp.conf` adds Wants/After dependencies so the
helper starts with the main tunnel. Other transports remain independent of
helper availability. Full client uninstall removes the helper, drop-in and
credentials too.

### Apply and rollback

```bash
bash client-linux/render.sh --vless-only
sudo bash client-linux/scripts/apply-config.sh
```

The apply script validates the main config with the installed binary, installs
and validates the optional helper, and saves the previous main config as
`/usr/local/anthropic-tunnel/etc/config.before-profiles.json` (root 600).
If the tunnel is active it restarts only that daemon, retaining DNS protection,
and restores the backup if startup fails. If the tunnel is inactive, it installs
the profiles/helper without starting either service. It preserves enablement.
Disable other VPN TUNs before using Connect afterwards.

To restore the previous main config while the tunnel is active:

```bash
sudo install -o root -g root -m 600 /usr/local/anthropic-tunnel/etc/config.before-profiles.json /usr/local/anthropic-tunnel/etc/config.json
sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh
```

Validated before applying: sing-box schema checks, Xray config test, systemd
unit syntax, authenticated HTTP API probes (401) and UDP DNS answers for all
six profiles, plus wrong-pin rejection. WebSocket's first UDP probe timed out;
a focused retest passed using explicit `packet_encoding: xudp`. Probe daemons
and files were removed. The imported config and helper are now installed: all six transports were
observed in the live Clash API and the helper service is running. Full TUN
transport switching and reboot tests remain pending.

## Direct sites fail on an IPv4-only uplink

Observed on 2026-10-29: Google HTTPS returned HTTP 200 with `curl -4`, but
ordinary curl and `curl -6` reset during TLS. The physical link had no IPv6
default route; the TUN supplied a synthetic ULA IPv6 address and accepted
connections that its direct outbound could not deliver (`network is unreachable`).
This can prevent applications from falling back to IPv4 after TCP has appeared
to connect.

For this machine, `private/secrets/linux-options.json` now contains:

```json
{"ipv4_only": true}
```

Rendering with this local option removes only the IPv6 address from the TUN;
it preserves the shared dual-stack template, all profiles, DNS and routing
rules. It does not disable IPv6 globally or send Google through the tunnel.
Use only on a host without native IPv6 connectivity; if the uplink gains IPv6,
remove the option (or set it false) and restore dual-stack TUN capture.

```bash
bash client-linux/render.sh --vless-only
sudo bash client-linux/scripts/apply-config.sh
```

The IPv4-only config passed sing-box validation and a render comparison proved
only the TUN address list changed. After the user applied it, ordinary Google
HTTPS returned HTTP 200. The active IPv6 policy contains an unreachable rule
with strict routing; the TUN no longer advertises a global/ULA IPv6 address.
The config apply script keeps DNS protection active and saves the previous
config for rollback.

## Startup failure: route already exists

If the journal reports `set routes: add route 0: file exists`, inspect both
`ip -4 route show table 2022` and `ip -brief link show`. Another sing-box TUN
can occupy the same default routing table even when no policy rules are
visible between failed startup attempts. Disable the other VPN's TUN mode in
its own application, verify its interface is gone, then run:

```bash
sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh
bash /usr/local/anthropic-tunnel/bin/status.sh
```

The restart script is allowed without a password after installation and leaves
the DNS protection unit running. Do not flush a shared routing table or remove
another VPN's routes by hand. Keep only one TUN active for this deployment;
coexistence has not been validated. A running daemon, six DNS domains, an up
TUN, fake-IP resolution and API HTTP 401 are the expected basic health results.

## Pieces

| Piece | Runs as | Started by | Purpose |
|---|---|---|---|
| sing-box 1.14.4 (TUN + DNS listener) | root | systemd `anthropic-tunnel.service` | routing, DNS, kill switch |
| DNS layer | root (oneshot) | systemd `anthropic-tunnel-dns.service` | the six apexes resolve only through sing-box, even when it is down |
| Indicator | user | GTK/AppIndicator + desktop login entry | Linux tray frontend reuses `menubar/anthropic-tunnel.5s.py` status/actions |

Files: `client-linux/` (config template, render.sh, systemd units,
scripts), `menubar/install-linux.sh`, `tests/linux-container/`. The
step-by-step runbook for the agent on the Ubuntu machine, including the
real-machine test matrix L1–L12, is `client-linux/README.md`.

## sing-box config (`client-linux/sing-box/config.template.json`)

The design notes below describe the original container-tested addresses; use
the updated Linux addresses in the preparation section for the current files.

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
| anthropic-dns0 (dummy link, 172.30.250.9/32) | DNS layer, created by the unit at boot | |
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

## Indicator (GTK/AppIndicator on Wayland)

`menubar/anthropic-tunnel-tray.py` provides the Linux tray frontend. It imports
status, icons, notifications and diagnostics from `anthropic-tunnel.5s.py`,
which remains the macOS SwiftBar frontend. On Ubuntu GNOME the existing Ubuntu
AppIndicators extension renders its StatusNotifierItem over the session D-Bus.
Argos is no longer required, and installation needs neither sudo nor logout.
Other Wayland desktops need their own StatusNotifierItem host; Wayland alone
does not supply a tray.

Requirements: system Python 3 with PyGObject, GTK 3 introspection, and either
AyatanaAppIndicator3 or AppIndicator3 introspection. Both namespace variants
are supported. These dependencies were already present on the tested machine.

```bash
bash menubar/install-linux.sh
# Relaunch manually, or search for Anthropic Tunnel in Applications:
~/.local/bin/anthropic-tunnel-indicator
# Quit only the indicator; the tunnel keeps running:
~/.local/bin/anthropic-tunnel-indicator --quit
# Remove the indicator and its login entry:
bash menubar/uninstall-linux.sh
```

The installer copies the frontend/backend to
`~/.local/share/anthropic-tunnel/`, adds the launcher under `~/.local/bin/`, and
writes `anthropic-tunnel.desktop` in both `~/.local/share/applications/` and
`~/.config/autostart/`. XDG overrides are honored for data/config/state/cache.
The old plugin `~/.config/argos/anthropic-tunnel.5s.py`, if present, is renamed
to `.anthropic-tunnel.5s.py.disabled`; other Argos plugins are untouched.

The indicator reads the installed Clash secret, refreshes every five seconds,
and keeps slow probes/actions off the GTK thread. It offers connection status,
connect/disconnect/restart, configured transports, aggregate statistics, log,
diagnostics, DNS cache flush and quit. Disconnect explicitly allows direct
access; quitting the indicator does not stop the tunnel. One D-Bus application
ID prevents duplicate instances. State/log files live under
`~/.local/state/anthropic-tunnel/`, icons under `~/.cache/anthropic-tunnel/`.

Verified on 2026-10-29: dependency check, desktop-file validation, live GNOME
registration with green icon/checkmark, exported menu showing a healthy VLESS
connection, single-instance launch, quit/relaunch and uninstall/reinstall without changing
the tunnel PID. GTK selected the native Wayland display backend. Login autostart is configured but has not yet been tested across logout.
The earlier container tests below exercised the Argos-compatible backend,
not the new GTK frontend.

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
the operator's go), remaining real-machine tests (failure, reboot, NetworkManager persistence
and, if used, Server with networkd), indicator login autostart, optional
`auto_redirect` (sing-box recommends it on Linux; it adds nftables rules and
redirects port 53 by itself; evaluate after the real-machine run).

## Live egress and startup verification (2026-10-29)

After applying the IPv4-only option, two ordinary public-IP observers agreed
on the direct connection's public IP. Both the Anthropic API and Claude's own
`/cdn-cgi/trace` endpoints reported the configured server's public IP and US
location. Google returned HTTP 200; live connection metadata showed direct
routing. A review of the current daemon invocation found 53 tunnelled
Anthropic log entries and zero direct matches among 421 lines. Exact IPs and
the machine-specific audit record remain in `private/secrets/egress-audit.json`.
These checks cover the sampled requests/logs, not every application/protocol.

Both main and DNS units are enabled at boot; the main daemon uses
`Restart=always` with a two-second delay. The persistent DNS unit has
`RemainAfterExit=yes` and does not stop when the daemon crashes. This is
DNS-based fail-closed protection for the configured suffixes, not a complete
firewall guarantee against bypasses. Explicit Disconnect removes DNS
protection and disables boot startup until Connect is used again. Real-host
crash/reboot tests and tray login autostart testing remain open.

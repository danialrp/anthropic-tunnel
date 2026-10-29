# Decisions log

Format: date · decision · why · alternatives rejected.

## 2026-10-28 · Domain-based TUN routing (sing-box) instead of IP routes or system proxy
Why: Anthropic IPs are dynamic (Cloudflare/AWS); TUN catches every app including
Chrome and Node CLIs that ignore system proxy; no-fallback config gives
fail-closed for free.
Rejected: system proxy/PAC (apps can bypass), full-tunnel WireGuard (mixes all
traffic through the server).

## 2026-10-28 · Server side in Docker Compose, bridged, own ports
Why: server already runs other VPN/WireGuard services; this stack must be
isolated and removable in one command.
Rejected: host-network container, installing sing-box on the host.

## 2026-10-28 · WireGuard first, VLESS+Reality second
Why: the operator switches internet connections; some block WireGuard. Start simple,
add the second transport with a selector so the menu bar can switch.

## 2026-10-28 · Menu bar with four states (green/yellow/red/grey)
Why: the operator wants to see at a glance whether the tunnel is up, whether
Anthropic traffic is flowing, and whether it is off on purpose.

## 2026-10-28 · English everywhere in repo and UI
Why: one language for code, UI and docs keeps the project readable for anyone
who clones it.

## 2026-10-28 · Six Anthropic apex domains are the tunnel rule set
anthropic.com, claude.ai, claude.com, claude.app, claudeusercontent.com,
claudemcpcontent.com (spec/02 Section A, from the official Desktop full list).

## 2026-10-28 · Third-party hosts stay OFF the tunnel (the operator's decision)
Rule 0 is about Anthropic's own servers. Providers with separate
infrastructure (GitHub, GitLab, npm, Cloudflare, Google buckets, Datadog) go
direct, even when an Anthropic product contacts them. Only the six apexes in
spec/02 Section A are tunnelled. Rejected: tunnelling Datadog intake hosts or
whole third-party apexes.

## 2026-10-28 · No code without the operator's explicit permission
Specs and docs may be written freely; any code, config, script or server
command that changes state waits for a direct go-ahead in chat for that step.
Stack recorded in spec/07-stack.md; approved by the operator the same day.

## 2026-10-28 · Server ports and subnets (after pre-flight)
WireGuard UDP 51820; VLESS+Reality TCP 8444 (phase 2); tunnel subnet
10.66.66.0/24 (checked against the Mac: no overlap). Compose bridge
172.30.0.0/24 was planned and then dropped the same day (see host-network
decision below).

## 2026-10-28 · Do not enable ufw on the server
No host firewall is active today. Turning one on would affect the other tenants' VPN services,
nginx and DNS that already run there, which rule 3 forbids. Our stack publishes
only its own ports.

## 2026-10-28 · Shared server: no host changes at all
The operator: colleagues also have root; the existing key is a colleague's. This
project never changes sshd, firewall, passwords, packages or any file outside
/opt/anthropic-tunnel. Password rotation removed from the plan. The operator's
`id_rsa.pub` appended to root's authorized_keys (the one host change he asked
for); all later access is by key.

## 2026-10-28 · Server must be in the United States (the operator's rule)
Any server used by this project must have a US-geolocated public IP. Current
server verified US on two services (details in `private/notes.md`). Added as
CLAUDE.md rule 11.

## 2026-10-28 · sing-box pinned to 1.14.4 on both ends
brew installed 1.14.4 (formula listed 1.14.3 as stable but bottled 1.14.4);
image tag v1.14.4 verified on ghcr. Same version both sides avoids config
drift. WireGuard as a sing-box `endpoint` (since 1.11), userspace, no caps.

## 2026-10-28 · Container runs with network_mode: host (supersedes "bridged")
Why: the shared host has a foreign `tcp dport 443 notrack` raw rule that
breaks Docker bridge NAT for port 443. Rule 3 forbids touching it. Host
networking needs no NAT; the container still binds only UDP 51820 and adds no
firewall rules. Rejected: editing the raw table (not ours), macvlan (one
public IP only), running sing-box on the host (not removable cleanly).

## 2026-10-28 · WireGuard MTU 1280 on both ends
Why: measured return-path MTU server→Mac is 1420; 1408 inner MTU overflowed
it. 1280 leaves margin for other connections the operator switches to.

## 2026-10-28 · Reality SNI = www.apple.com
Why: reachable from the server with TLS 1.3 in ~70 ms, plausible destination
for a Mac, not an Anthropic or Iranian-sensitive domain. Rejected:
www.microsoft.com (slower), dl.google.com (redirects), cloudflare (CDN).

## 2026-10-29 · Ubuntu client: same design, systemd + resolved routing domains
Why: the operator wants the client on Ubuntu with identical behaviour. macOS has
/etc/resolver files; Ubuntu (Desktop and Server) has systemd-resolved, whose
per-link routing domains never fall back to other servers. A persistent
dummy link (anthropic-dns0, 172.19.0.9/32) carries the six routing domains and
points at a sing-box `direct` inbound on that same address; the TUN runs with
`dns_mode: disabled` so sing-box does not take over all system DNS.
Rejected: dns_mode hijack (sing-box sets the TUN as DNS route for every
domain and the setting dies with the TUN); DNS server on the TUN address via a
dummy link (resolved binds the socket to the dummy, packets are dropped); a
loopback listener (works for the six domains but resolved also uses it for
every other name); nftables string matching (a second mechanism to maintain).

## 2026-10-29 · Linux sing-box from the release tarball, not the .deb
Why: the .deb installs its own sing-box.service, a sing-box user, polkit and
D-Bus policies for resolved. We want one root-owned binary under
/usr/local/anthropic-tunnel like on macOS. The tarball sha256 for both
architectures is pinned in install.sh (the release ships no checksum file).

## 2026-10-29 · One WireGuard peer per client
Why: a WireGuard peer is one session; a second client on the Mac's key would
steal the endpoint and cut the Mac's line (rule 12). The Linux client has its
own key (private/secrets/wg-linux.key) and address 10.66.66.3/32; the server template
carries both peers. VLESS keeps one UUID (multi-session by design).

## 2026-10-29 · One indicator file for both platforms
Why: Argos on GNOME speaks the BitBar format that SwiftBar extends, so the
plugin branches on sys.platform instead of being forked; the macOS output was
diffed before and after and is unchanged. Rejected: an AppIndicator Python app
(needs python3-gi and GTK typelibs, a second code base).

## 2026-10-29 · README as the public entry point
Why: a new operator needs one page that says what the project does, why, how
it works, and every setup step from an empty clone (secrets generation tested
in a throwaway copy before publishing). MANUAL.md holds daily operations;
specs hold the design. Plugin and icon generator use `#!/usr/bin/env python3`;
`menubar/install.sh` pins the interpreter it finds, so Intel and Apple Silicon
Macs both work.

## 2026-10-29 · One git-ignored private/ folder for all operator data
Why: the repository is shared by every operator who clones it. A single folder
that git ignores as a whole (`private/`: private/secrets/, notes.md, backups/) is
easier to keep right than several ignore rules, and the same convention works
for every operator and agent. The render scripts read `private/secrets/`.
CLAUDE.md rule 4 states it, including a staged-diff check before every
commit. Rendered configs and downloaded binaries stay where the scripts write
them, as git-ignored build outputs. Rejected: separate ignored locations for
keys and notes (two places to remember).

## 2026-10-29 · VLESS-only Linux bootstrap and separate Linux TUN addresses

Use the already-deployed project VLESS/Reality listener for Linux setup without
reusing the Mac WireGuard peer or changing the shared server. Add an explicit
`--vless-only` render mode that requires only VLESS connection secrets and a
local API secret, removes WireGuard, and selects VLESS by default. Preserve
the existing dual-transport render mode for a future deployed Linux peer.

Move Linux IPv4 TUN/DNS addresses to `172.30.250.1/30` and `172.30.250.9/32`
because the previous TUN address overlaps an existing local Docker bridge.
Keep the Linux scripts and indicator in sync; macOS stays on its original
addresses. The new range is verified free on the setup machine, not guaranteed
free on every host. No Docker networks or server services were changed.

## 2026-10-29 · One active Linux TUN during this deployment

An existing VPN resumed using table 2022 and prevented the project daemon from
adding its default route. The user disabled that VPN's TUN, and restarting the
project daemon restored service while retaining the DNS protection layer.
Keep the other TUN off; changing only the table number would not establish
correct coexistence between two sets of DNS and routing rules. Do not flush
another application's routing table as a startup workaround.

## 2026-10-29 · Replace Linux Argos frontend with GTK/AppIndicator

The user requested a tray app for the current Wayland session. Use the already
available GTK 3/AppIndicator bindings and Ubuntu AppIndicators host, avoiding
the session restart required to load newly installed Argos. Keep the existing
Python module as the shared status/icon/action backend and leave macOS SwiftBar
behaviour unchanged. Probes run off the UI thread; a D-Bus application ID
ensures one instance. Desktop autostart runs as the user, with the existing
limited sudoers actions for tunnel controls. Supersedes the Argos choice above.

## 2026-10-29 · Preserve imported profiles and isolate XHTTP

The user requested all existing server connection profiles. Keep extra
credential-bearing outbounds under `private/secrets/extra-outbounds.json` and merge
them when rendering, rather than putting credentials into the template or
losing imports on regeneration. Preserve the working default and fail-closed
routing. Import only client connection endpoints, not administration listeners;
WireGuard still requires a distinct deployed Linux peer.

Use explicit SSH-authenticated SPKI pins for the expired/self-signed TLS
profiles instead of accepting arbitrary certificates. For XHTTP, add a pinned
Xray helper behind authenticated loopback SOCKS, with no route management and
no direct fallback. It runs as a systemd dynamic user with a credential file.
Applying profiles preserves the user's current off/on state; an inactive
tunnel stays off, especially when another VPN TUN is active.

## 2026-10-29 · Per-machine IPv4-only TUN option

A synthetic TUN IPv6 address made ordinary direct connections select IPv6 on
an uplink with no IPv6 default route. Google worked over IPv4 but reset after
TCP establishment over the TUN's unusable IPv6 path. Add a private
`linux-options.json` setting that removes the TUN IPv6 address only on this
machine. Preserve dual-stack defaults for machines with native IPv6; do not
change global IPv6 settings or route third-party sites through the server.

## 2026-10-29 · Preserve the replacement repository conventions

Base the Linux PR on the replacement repository's main commit instead of
merging the deleted repository's unrelated history. Use `private/secrets/`
for client credentials and the English `MANUAL.md` for operator commands.
Parse indicator inputs as JSON: the new renderer uses multiline output and
VLESS-only configs have no WireGuard peer from which to extract an address.

## 2026-10-29 · Packet-level leak guard on each client (macOS pf, Linux nftables)
Why: with another VPN active, or with sing-box down and an app that resolves
names itself (DNS over HTTPS) and connects to a real address, the DNS layer
alone cannot stop a direct connection. A filter below the routing decision
refuses every packet to Anthropic addresses that does not leave through our
TUN, whatever owns the routes. Addresses: Anthropic's own ranges, sing-box
fake-IP ranges, and load-balancer addresses of Anthropic hosts resolved
through the tunnel. Hosts behind shared CDNs are excluded so unrelated sites
never break. Rules sit in our own pf anchor under Apple's com.apple/* hook
(no edit to /etc/pf.conf) and in our own nftables table on Linux; a 5 s check on
macOS repairs pf being disabled, Apple's ruleset being flushed and the utun
number changing. The installer self-tests and rolls itself back if Anthropic
stops answering through the tunnel. Rejected: matching packets by source
address 172.19.0.1 (an app can bind it while the route points elsewhere);
blocking whole CDN ranges (breaks other sites); a NetworkExtension filter
(signed app, out of scope). Proxies above the IP layer cannot be filtered;
the indicator detects and reports them instead.

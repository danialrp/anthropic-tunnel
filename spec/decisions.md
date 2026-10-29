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
server verified US on two services (details in `spec/private.md`). Added as
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
own key (secrets/wg-linux.key) and address 10.66.66.3/32; the server template
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
that git ignores as a whole (`private/`: secrets/, notes.md, backups/) is
easier to keep right than several ignore rules, and the same convention works
for every operator and agent. The render scripts read `private/secrets/`.
CLAUDE.md rule 4 states it, including a staged-diff check before every
commit. Rendered configs and downloaded binaries stay where the scripts write
them, as git-ignored build outputs. Rejected: separate ignored locations for
keys and notes (two places to remember).
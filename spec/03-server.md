# 03 — Server

Host: see `private/secrets/server.env` (never commit the IP). Access as root by SSH
key only (key path in `private/secrets/server.env`). Assume the server is shared with
other people who also have root; see CLAUDE.md rule 3.

## Location rule (CLAUDE.md rule 11)

The server IP must geolocate to the United States. Verified 2026-10-28 for the
current server on two services (ipinfo.io, ip-api.com): United States.
Provider, city and ASN are in `private/notes.md`. Re-check and record there
whenever the server or its IP changes.

## Constraints (from CLAUDE.md rule 3)

- Standalone Docker Compose stack under `/opt/anthropic-tunnel/` on the server.
- Must not interfere with existing WireGuard / VPN containers or host services.
- Removable completely with `docker compose down -v` plus deleting the folder.

## Pre-flight (read-only, before any decision)

```
docker ps --format '{{.Names}} {{.Ports}}'
ss -lunp ; ss -ltnp          # ports already in use
ip addr ; ip route           # existing wg interfaces and subnets
cat /etc/os-release ; docker --version ; docker compose version
```
Ports and the WireGuard subnet for this stack are chosen only after this output
is seen, and recorded in `decisions.md`.

## Stack (written 2026-10-28)

`server/docker-compose.yml`, project name `anthropic-tunnel`
- service `sing-box`, image `ghcr.io/sagernet/sing-box:v1.14.4` (tag verified
  to exist via `docker manifest inspect`), container
  `anthropic-tunnel-sing-box`
- WireGuard runs in userspace inside sing-box (`system: false`), so no
  `NET_ADMIN`, no `/dev/net/tun`, no kernel module. The container has no
  extra capabilities.
- publishes only `51820/udp` (phase 1); `8444/tcp` is added in phase 2
- `network_mode: host` (changed 2026-10-28 during deployment, see below);
  the container binds only UDP 51820 on the host
- `restart: unless-stopped`, `mem_limit: 128m`, `cpus: 0.5`, json-file logs
  capped at 3×10 MB
- named volume `anthropic-tunnel-data` for sing-box's working dir
- config mounted read-only from `server/sing-box/config.json`

`server/sing-box/config.template.json` → rendered by `server/render.sh`
(POSIX sh, `sed` placeholder substitution from `private/secrets/`) into
`config.json` (git-ignored). Validated locally with `sing-box check`.
- one `wireguard` endpoint `wg-in`: address 10.66.66.1/24, listen 51820,
  MTU 1280, one peer (the Mac) allowed_ips 10.66.66.2/32, pre-shared key set.
  Since 2026-10-29 the template carries a second peer for the Linux client
  (`private/secrets/wg-linux.pub`, 10.66.66.3/32, same PSK); **not deployed yet**
  (todo 5), the running server still has the Mac peer only.
- outbounds `direct` and `block`; `route.final = direct`
- The server does no DNS and no domain logic: it forwards whatever the Mac
  sends, and the Mac only sends Anthropic traffic.

Tunnel subnet 10.66.66.0/24 checked against the Mac's local networks on
2026-10-28 (listed in `private/notes.md`). No overlap.

## Deployment (what `up` creates on the server, nothing else)

1. `/opt/anthropic-tunnel/docker-compose.yml`
2. `/opt/anthropic-tunnel/sing-box/config.json` (mode 600)
3. Docker image `ghcr.io/sagernet/sing-box:v1.14.4` pulled
4. Docker volume `anthropic-tunnel-data`
5. Container `anthropic-tunnel-sing-box` in the host network namespace,
   listening UDP 51820. No nftables/NAT rules are added by Docker in host mode.

## Deployment log and verification (2026-10-28)

Deployed as above. Two problems found and fixed, both inside our own config:

1. **Bridge NAT impossible for port 443.** The host's `ip raw` table (owned by
   another tenant's tool, named in `private/notes.md`) has `tcp dport 443 notrack`. Without
   conntrack, Docker's MASQUERADE cannot NAT, so container SYNs to any :443
   left eth0 with source 172.30.0.2 (confirmed with tcpdump) and timed out.
   UDP and port 80 worked. Host firewall is off-limits (rule 3), so the stack
   was switched to `network_mode: host`, which needs no NAT. Verified with a
   throwaway host-network container before changing the stack. The bridge
   network was removed; `nft list ruleset` contains nothing of ours.
2. **Path MTU 1420 from server to Mac.** With WireGuard MTU 1408 the outer
   packet is 1468 bytes; the kernel's cached PMTU to the Mac was 1420
   (`ip route get`), DF pings above 1400 bytes failed. sing-box logged
   `sendmmsg: message too long`. MTU set to 1280 on both ends (safe for any
   of the operator's connections). Mac→server PMTU was 1500; the limit is on the
   return path.

End-to-end test from the Mac (temporary sing-box client with a local SOCKS
inbound, no TUN, no root; config kept outside the repo):

| Check | Result |
|---|---|
| Public IP direct | the Mac's own public IP |
| Public IP via tunnel | the server's IP |
| api.anthropic.com/v1/models | HTTP 401 (expected without key) in 0.9 s |
| platform.claude.com | HTTP 200 |
| console.anthropic.com | HTTP 301 |
| claude.ai, downloads.claude.ai | HTTP 403 to plain curl, see note |
| Server-side errors | none after MTU fix |
| Container memory | ~9 MiB of 128 |
| Other tenants' host services (see `private/notes.md`) | all still active |

Note on 403: claude.ai answers 403 to curl's default user agent; whether the
server IP is treated differently from the Mac's is checked in the same step
(see history.md) and finally in a real browser once the TUN client is up.

Phase 1: WireGuard inbound → direct outbound.
Phase 2 (deployed 2026-10-28): VLESS inbound `vless-in` on TCP 8444, user
`mac` with flow `xtls-rprx-vision`, TLS Reality with handshake target
www.apple.com:443 (checked reachable from the server, TLS 1.3), private key
and 8-hex-digit short_id from `private/secrets/`, `max_time_difference 1m`. Because
VLESS carries domain names, the server now has a `dns.servers: local` entry
and `route.default_domain_resolver: local`. Still `final: direct`.

## Firewall on the server

None is active and this project changes nothing there. Docker publishes the two
ports itself through its own nftables chains, which Docker also removes on
`compose down`.

## Removal

```
cd /opt/anthropic-tunnel && docker compose down -v && cd / && rm -rf /opt/anthropic-tunnel
```
plus removing the two firewall rules. Nothing else changes.

## Pre-flight results (read-only, 2026-10-28)

Host: a small shared VPS, Ubuntu 24.04, x86_64. Provider, exact versions,
CPU/RAM/disk and the other tenants' services are in `private/notes.md`.

| Item | Found |
|---|---|
| Resources | 1 vCPU, under 1 GiB RAM, small disk mostly used; enough for one sing-box container |
| Docker | 29.4.0, Compose v5.1.2, cgroup v2, overlayfs, **0 containers** (none exist); daemon.json: experimental + ip6tables |
| Docker networks in use | the default bridge plus two unused bridges in 172.17/172.18/172.28 (names in `private/notes.md`) |
| Existing VPNs | several run on the **host** as systemd units, not Docker (names and paths in `private/notes.md`) |
| WireGuard | none: no wg interfaces, no /etc/wireguard, kernel module not loaded. sing-box's WireGuard is userspace, so no module is needed. |
| Ports in use | TCP 22, 80, 443, 2053, 8443, 9999; UDP 53, 8443, plus random high UDP ports; several loopback-only ports (owners in `private/notes.md`) |
| Candidate ports | UDP 51820, 51821, 51822, 36000 free; TCP 8444, 2096, 2087, 2083, 36000 free |
| Firewall | ufw installed but **inactive**; nftables holds only Docker's own chains. No host firewall: every listening port is reachable from the internet. |
| ip_forward | 1 (already on) |
| /dev/net/tun | present, world rw |
| DNS | 8.8.8.8, 1.1.1.1 |
| sshd | PermitRootLogin yes, PasswordAuthentication yes (cloud-init drop-in) |
| root authorized_keys | exactly one key, a colleague's (identity in `private/notes.md`). **Not the operator's key.** Flagged for the operator's decision; nothing changed. |
| Cron | acme.sh daily (certs for the other tenants' services), certbot, sysstat |

## Consequences for the design

- Isolation is simple: nothing else uses Docker, so our stack is the only
  Compose project. It must still not touch the host's existing VPN units.
- Port plan (recorded in decisions.md): WireGuard inbound **UDP 51820**,
  VLESS+Reality inbound later **TCP 8444**. Both verified free.
- Compose network: dedicated bridge **172.30.0.0/24** (does not overlap
  172.17/172.18/172.28). WireGuard tunnel subnet **10.66.66.0/24** (checked
  against the Mac's networks before use, not assumed).
- Memory: sing-box idle ~20–40 MiB; fits. Add `mem_limit: 128m` so a leak can
  never starve the host services.
- No host firewall exists, so "open a port" is a no-op today. We do not enable
  ufw (that would change behaviour for every other service). If the operator later
  enables a firewall, our two ports go in by name.
- The existing key belongs to a close colleague of the operator (see
  `private/notes.md`). It stays. No sshd or firewall hardening by this project.

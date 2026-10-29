# 01 — Architecture (as deployed 2026-10-28; Linux client added 2026-10-29, see 08)

```
 Mac (client)                                        Server (Docker, host network)
 ┌────────────────────────────────────┐              ┌──────────────────────────────┐
 │ apps: Chrome, Claude.app, claude   │              │ container anthropic-tunnel-  │
 │ CLI, hooks, MCP, curl ...          │              │ sing-box (sing-box 1.14.4)   │
 │     │ DNS for 6 Anthropic apexes   │  WireGuard   │  in: wireguard  UDP 51820    │
 │     │ → /etc/resolver → 172.19.0.2 │  UDP 51820   │  in: vless+Reality TCP 8444  │
 │     ▼                              │ ───────────► │          │                   │
 │ utun (sing-box TUN, 172.19.0.1)    │  or VLESS    │          ▼                   │
 │  ├─ DNS: fake-ip 198.18.x for      │  TCP 8444    │  out: direct → api.anthropic │
 │  │   Anthropic names; others →     │ ───────────► │       .com, claude.ai, …     │
 │  │   normal system resolver        │              └──────────────────────────────┘
 │  ├─ route: Anthropic domains / IPs │
 │  │   → selector "anthropic"        │   selector = [wg-out, vless-out], no direct
 │  ├─ route: everything else → direct│
 │  └─ no fallback for Anthropic      │
 │ launchd daemon (root, KeepAlive)   │
 │ SwiftBar plugin (user, 5 s)        │
 │   reads Clash API 127.0.0.1:9090   │
 └────────────────────────────────────┘
```

## Components

1. **Server stack** (`server/`): Docker Compose project `anthropic-tunnel`,
   one `sing-box` container in `network_mode: host` (a foreign `notrack` rule
   on the shared host breaks bridge NAT for port 443, see 03). It binds only
   UDP 51820 (WireGuard endpoint) and TCP 8444 (VLESS+Reality inbound) and
   forwards everything to `direct`. No DNS or domain logic beyond a local
   resolver for names carried by VLESS. Removable with `docker compose down -v`.
2. **Client** (`client/`): sing-box 1.14.4 as a system launchd daemon
   (`local.anthropic-tunnel`, binary and config under
   `/usr/local/anthropic-tunnel/`), TUN inbound with `auto_route`, fake-IP DNS
   for the six apexes, route rules by domain suffix, Anthropic IP range and
   sniffed SNI, selector `anthropic` = [`wg-out`, `vless-out`] with no direct
   member, six `/etc/resolver` files pointing the apexes at the TUN DNS,
   sudoers entry for the up/down/restart scripts. Details in 04.
3. **Menu bar** (`menubar/`): SwiftBar 2.1.1 plugin
   (`anthropic-tunnel.5s.py`) reading the Clash API every 5 s: four states,
   stats, transport switch, connect/disconnect/restart. Details in 05. The
   same file runs under Argos on Ubuntu GNOME.
4. **Linux client** (`client-linux/`): the Mac client translated to Ubuntu:
   systemd `anthropic-tunnel.service` (sing-box, root), a persistent dummy
   link `anthropic-dns0` whose systemd-resolved routing domains send the six
   apexes only to a sing-box DNS listener on that link's address (the
   `/etc/resolver` equivalent, fail-closed), own WireGuard peer
   `10.66.66.3/32`. Details in 08.

## Data flow for one request to api.anthropic.com

1. App asks the system resolver. `/etc/resolver/anthropic.com` sends the query
   to 172.19.0.2, which is the TUN's DNS address, hijacked into sing-box.
   The DNS rule returns a fake IP (198.18.0.x). HTTPS/SVCB queries for these
   names are rejected so no real IP hints reach the app.
2. App connects to the fake IP → packet enters utun → sing-box maps it back to
   the name → route rule `domain_suffix` → selector `anthropic` → the chosen
   transport (WireGuard by default).
3. sing-box looks up the real IP through the tunnel (`dns-tunnel` = 1.1.1.1
   via the selector) and sends the connection. The server forwards it direct.
4. If the chosen transport is down: the connection fails (timeout). No other
   route exists for the name. RED in the menu bar after two failed probes.

## Belt and braces

- App that resolves by itself (own DoH) and connects to a real IP: the packet
  still enters utun (default route) and is matched by the Anthropic IP-range
  rule (160.79.104.0/23, 2607:6bc0::/48) or by the sniffed TLS SNI.
- App that binds to en0 to bypass the TUN: the name resolves to a fake IP that
  has no route on en0; the connection fails.
- Daemon crash: launchd restarts it in about a second; in the gap the resolver
  files point at a DNS that does not exist and fake IPs have no route, so
  nothing leaks.

## Why domain rules, not IP routes

Anthropic sits behind Cloudflare/Google/AWS edges for its CDN hosts; IPs
change. Suffix rules plus fake-IP DNS catch every subdomain regardless of IP,
and work for every app on the system because the TUN sits below the socket
layer.

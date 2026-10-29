# 00 — Overview

**Status (2026-10-29):** phases 1 and 2 LIVE on the Mac. Server: WireGuard (UDP 51820) + VLESS+Reality (TCP 8444). Mac: launchd daemon, resolver files, sudoers control, SwiftBar indicator with transport switch. Tests T1–T7, T9, T10 passed, T8 dry-reviewed. Ubuntu Linux client written (spec/08): systemd units, resolved-based fail-closed DNS layer, same indicator plugin via Argos; passed the container test on the Mac, not yet run on a real Ubuntu machine; its WireGuard peer is in the server template but not deployed. Optional later: pf third layer, log review for unexpected direct Anthropic hosts.

## Goal

A private, always-on, fail-closed tunnel between the operator's Mac and a dedicated
server, carrying ALL traffic to the Anthropic/Claude ecosystem and nothing else.

## Non-negotiable principle (Rule 0, see CLAUDE.md)

All Anthropic traffic, from every application and every path (browser tabs
including Chrome, desktop app, Claude Code CLI, SDKs, plugins, hooks, MCP,
Chrome extension, OAuth/login, updates, telemetry), goes through the tunnel.
Tunnel down = that traffic blocked. Never direct.

## Scope

In scope
- Server: one standalone Docker Compose stack, removable in one command.
- Mac: sing-box in TUN mode as a system launchd daemon; domain-suffix routing;
  fake-IP DNS for matched domains; no DIRECT outbound for them.
- Ubuntu Linux client with the same behaviour: sing-box TUN as a systemd
  service, systemd-resolved routing domains as the fail-closed DNS layer,
  own WireGuard peer (spec/08).
- Menu bar indicator (SwiftBar) with state colours, live stats, manual control.
- Protocols: WireGuard first; VLESS+Reality added as a second transport because
  The operator switches between internet connections and some block WireGuard.
- A packet-level leak guard on macOS (pf, spec/04): nothing reaches an
  Anthropic address except through the tunnel, even with the daemon down or
  another VPN active.

Out of scope
- Routing non-Anthropic traffic through the server.
- Any change to other services already running on the server.

## Threat / failure model

| Situation | Required behaviour |
|---|---|
| Server unreachable | Anthropic connections refused; indicator RED |
| sing-box crashes | launchd restarts it; while down, TUN is gone and DNS for Anthropic domains must not resolve directly (see 04 for how this is enforced) |
| App uses its own DoH / hard-coded IP | Refused by the leak guard unless it goes through the tunnel (Anthropic ranges plus resolved load-balancer addresses); hosts on shared CDNs are covered only by domain routing |
| Another VPN takes the routes | Leak guard refuses Anthropic outside our TUN: Anthropic stops working, nothing leaks |
| System proxy or NetworkExtension transparent proxy | Cannot be filtered at packet level; indicator turns red (`PROXY`) and notifies |
| The operator disables the tunnel manually | Allowed, explicit, indicator GREY, traffic goes direct knowingly |

## Language

Everything in the repo and in the product UI is English. Chat is in the
operator's language.

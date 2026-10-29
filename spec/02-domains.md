# 02 — Anthropic domains (source of truth for routing rules)

**Status:** researched 2026-10-28 by a Sonnet agent from official docs plus live
redirect checks. Rules in `client/sing-box/` are generated from Section A and
from whichever Section C entries the operator approves (see `decisions.md`).
Match type is `domain_suffix`, so every subdomain is covered.

## A. Anthropic-owned apex domains → TUNNEL (suffix rules)

The only official wildcard list is the Claude Desktop "Full list" (S2). It
names six apex domains:

```
anthropic.com
claude.ai
claude.com
claude.app              (*.livepreview.claude.app)
claudeusercontent.com   (artifacts, *.frame.*, bridge.* for Chrome extension)
claudemcpcontent.com    (MCP apps / widgets)
```

No other Anthropic-owned apex was found in any official document.

## B. Hostnames observed, by product (all fall under Section A)

### B1. API, console, docs, status
| Host | Role | Source |
|---|---|---|
| api.anthropic.com | Claude API, feature flags, telemetry, Remote Control, Agent SDK; SDK default base URL | S1 S3 S5 S6 S7 S8 |
| platform.claude.com | Console, docs, OAuth token exchange/refresh/revoke | S1 S6 |
| docs.anthropic.com, docs.claude.com | 301 → platform.claude.com/docs | S11 |
| console.anthropic.com | 301 → platform.claude.com; sign-in fallback page | S11 S10 |
| status.claude.com (status.anthropic.com → 301) | Status page | S4 S11 |
| support.claude.com (support.anthropic.com → 301) | Help center | S11 |
| code.claude.com | Claude Code docs, WebFetch doc lookups | S1 |
| www.anthropic.com, privacy.anthropic.com, trust.anthropic.com | Marketing/legal | S3 S5 |
| claude.com, www.claude.com | Sign-in entry, redirects to claude.ai | S1 S11 |

Inbound IP ranges published by Anthropic: 160.79.104.0/23, 2607:6bc0::/48 (S9).
Not used for routing (dynamic edge IPs elsewhere).

### B2. claude.ai web app
| Host | Role | Source |
|---|---|---|
| claude.ai | App, auth, claude.ai/code, installer script, Desktop download redirect | S1 S2 S12 |
| a.claude.ai, assets.claude.ai, downloads.claude.ai | Desktop "Reduced list"; purpose not stated | S2 |
| *.livepreview.claude.ai, *.livepreview.claude.app | Dynamic | S2 |
| a-api.anthropic.com, a-cdn.anthropic.com, s-cdn.anthropic.com, assets-proxy.anthropic.com | CDN/app code; blocking gives blank page | S1 S2 |
| *.claudeusercontent.com | Artifacts (*.frame.claudeusercontent.com) | S1 S2 |
| *.claudemcpcontent.com | MCP apps | S1 S2 |
| sso.claude.com | SSO sign-in (live 200) | S1 S2 S11 |

### B3. Claude Code CLI
| Host | Role | Source |
|---|---|---|
| api.anthropic.com | API, flags, telemetry | S1 |
| claude.ai, claude.com, platform.claude.com, sso.claude.com | Sign-in / OAuth | S1 |
| mcp-proxy.anthropic.com | claude.ai MCP connectors (live 404 on /, host exists) | S1 S11 |
| downloads.claude.ai | Native installer, auto-updater, version manifest, plugin binaries, apt/dnf/apk repos and keys | S1 S13 S14 |
| claude.ai/install.sh, /install.ps1, /install.cmd | Installer scripts | S13 |
| bridge.claudeusercontent.com | Chrome extension WebSocket bridge; Remote Control; cloud handoff | S1 S2 S15 |
| *.frame.claudeusercontent.com | Artifact reads | S1 |
| code.claude.com | Doc lookups | S1 |

Remote Control: outbound HTTPS only to the API (S8). Cloud sessions: claude.ai/code (S4).

### B4. Claude Desktop (macOS)
| Host | Role | Source |
|---|---|---|
| claude.ai/api/desktop/darwin/universal/dmg/latest/redirect | Download | S12 |
| claude.com/download | Download/update page | S12 |
| Full wildcard list (Section A) | Network requirements | S2 |

### B5. Chrome extension, Slack, Agent SDK, Managed Agents
- Chrome extension: bridge.claudeusercontent.com + claude.ai sign-in hosts; local
  native-messaging host makes no network calls (S1 S15).
- Slack / Claude Tag: cloud sessions at claude.ai/code; Anthropic reaches
  user services from 160.79.104.0/21 (S9 S16).
- Agent SDK: api.anthropic.com (S7).
- Managed Agents: api.anthropic.com; self-hosted sandbox list not fetched (D7).

## C. Non-Anthropic hosts that Anthropic products use

**Decision 2026-10-28 (the operator): none of these go through the tunnel.** Rule 0
covers traffic to Anthropic's own servers. A third party with its own
infrastructure (GitHub, GitLab, npm, Cloudflare CDNs, Google buckets, Datadog
as Anthropic's telemetry vendor) is not an Anthropic server and goes direct.
The table stays here as documentation of what the products contact, so that a
direct connection to one of them is recognised as expected, not as a leak.

| Host | Needed by | Optional? | Source |
|---|---|---|---|
| http-intake.logs.us5.datadoghq.com | Claude Code telemetry | yes (DISABLE_TELEMETRY) | S1 |
| browser-intake-us5-datadoghq.com | Claude Code error reports | yes (DISABLE_ERROR_REPORTING) | S1 |
| registry.npmjs.org | npm/bun installs, npm plugins, npx MCP servers | no, if used | S1 |
| github.com | Plugin marketplaces incl. official anthropics/claude-plugins-official | no, if used | S1 S5 |
| raw.githubusercontent.com | Release-notes feed at startup | background | S1 |
| storage.googleapis.com | Plugin install counts; native installer before CC 2.1.116; feedback uploads | partly | S1 S3 |
| formulae.brew.sh | Version check on Homebrew installs | only brew installs | S1 |
| *-review.googlesource.com | Gerrit lookup, Desktop only | optional | S1 |
| fonts.googleapis.com, fonts.gstatic.com | Artifact fonts | optional | S1 S2 |
| cdnjs.cloudflare.com, cdn.jsdelivr.net, cdn.tailwindcss.com, code.jquery.com, unpkg.com | Artifact libraries | no fallback if blocked | S1 S2 |
| registry.modelcontextprotocol.io | MCP registry (community-run) | unverified for CC | S17 |
| aws-external-anthropic.{region}.api.aws | Only Claude on AWS (AWS infra, not Anthropic) | n/a | S18 |

Legacy (no longer in current docs, present in old init-firewall.sh and Claude
Science docs only): sentry.io, o1158394.ingest.us.sentry.io, statsig.com,
*.mcp.claude.com (covered by claude.com anyway), api.github.com,
codeload.github.com, VS Code marketplace hosts (Microsoft).

## D. Unverified items (how to close each)

1. macOS Desktop auto-update host: not documented. Verify by watching sing-box
   connection log during an update check. Expected to fall under Section A.
2. Purpose of each Desktop "Reduced list" host: not stated; covered by A anyway.
3. Third-party hosts loaded by the claude.ai web page (analytics, Stripe,
   Google/Apple sign-in): no official list. Verify with a browser HAR capture
   after the tunnel is up; sing-box log will show them as direct.
4. Claude Code MCP registry host: not confirmed. Verify with `claude --debug`
   and the sing-box log.
5. Env-vars and errors docs were read only to 100 KB; connectivity-check hosts
   stated as api.anthropic.com and platform.claude.com.
6. Chrome extension: only bridge.claudeusercontent.com documented.
7. Managed Agents self-hosted sandbox network list: not fetched.
8. Whether api.anthropic.com resolves inside 160.79.104.0/23: not checked
   (irrelevant to suffix routing).

**Ground truth after deployment:** sing-box logs every connection with the
matched rule and outbound. First week of logs is reviewed and any host that
touches Anthropic but went direct is added here with the date.

## E. Sources

- S1 https://code.claude.com/docs/en/network-config
- S2 https://code.claude.com/docs/en/desktop (Network access requirements)
- S3 https://code.claude.com/docs/en/data-usage
- S4 https://code.claude.com/docs/en/claude-code-on-the-web
- S5 https://code.claude.com/docs/en/cloud-environments
- S6 https://claude.com/docs/claude-science/network-requirements.md
- S7 https://code.claude.com/docs/en/agent-sdk/hosting
- S8 https://code.claude.com/docs/en/remote-control
- S9 https://platform.claude.com/docs/en/api/ip-addresses
- S10 S6, "Domains the member's browser loads"
- S11 live curl redirect/status checks on 2026-10-28
- S12 https://code.claude.com/docs/en/desktop, /desktop-quickstart
- S13 https://code.claude.com/docs/en/setup
- S14 https://code.claude.com/docs/en/troubleshoot-install
- S15 https://code.claude.com/docs/en/chrome
- S16 https://claude.com/docs/claude-tag/admins/network-requirements.md
- S17 web search, third-party results only
- S18 https://code.claude.com/docs/en/env-vars
- S19 https://raw.githubusercontent.com/anthropics/claude-code/main/.devcontainer/init-firewall.sh
- S20 https://code.claude.com/docs/en/devcontainer
- S21 https://code.claude.com/docs/en/mcp
- S23 https://code.claude.com/docs/en/errors
- SDK defaults: anthropic-sdk-python `_client.py`, anthropic-sdk-typescript `client.ts`
- S24 https://code.claude.com/docs/en/slack

## Maintenance

- Re-run the research when a product is added or Anthropic announces a host.
- Any domain added by hand carries a source line (URL, or "seen in sing-box log on <date>").

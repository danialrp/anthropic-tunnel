# anthropic-tunnel — rules for agents

This file holds only rules, security constraints and things an agent must know
before acting. Everything else (architecture, decisions, history, how-tos) lives
in `spec/` and is linked from here. Keep this file short.

"The operator" below is the person who cloned this repo and runs it on their
own machines and server. If you are an agent reading this for the first time:
read this file, then `README.md`, then the spec for the machine you are on
(`spec/04` for macOS, `client-linux/README.md` for Linux, `spec/03` for the
server). Chat with the operator in whatever language they use; everything you
write into the repo is English.

## Rule 0 — the one that cannot be negotiated

**Every byte exchanged with anything Anthropic-owned goes through the tunnel.
No exceptions, no fallback, no "temporary" direct path.** This covers every
product and every path: claude.ai in any browser, the Claude desktop app,
Claude Code CLI, the Agent SDK, plugins, hooks, MCP servers that talk to
Anthropic, the Chrome extension, logins and OAuth, downloads, updates,
telemetry. If the tunnel is unavailable, that traffic is **blocked**
(fail-closed), never routed directly. Any change that weakens this is
rejected, whoever asks.

The authoritative domain list is `spec/02-domains.md`. Rules match by domain
suffix so new subdomains are covered automatically.

## Hard rules

1. **No assumptions, ever.** Do not act on a guess about the server, the
   client machine, a config key, a port, a domain, or a tool's behaviour.
   Verify first (read the file, run the read-only command, check the dated
   source). If it cannot be verified, say so and stop.
2. **Fail-closed by design.** Every component is written so that its failure
   blocks Anthropic traffic instead of leaking it. A "DIRECT" outbound for an
   Anthropic domain must never exist in any config.
3. **Server isolation. Assume the server is SHARED** with other people who
   also have root. This project lives only inside its own Docker Compose stack
   under `/opt/anthropic-tunnel/` (`server/`). It must not touch, read, modify,
   restart or depend on any other container, service, unit, firewall rule,
   sshd setting, cron, package or file on that host. No firewall changes, no
   sshd changes, no password changes, no package installs outside the
   container. Removing the stack must leave the server exactly as it was.
   Before any server command that writes, list what it will change and get
   the operator's confirmation.
4. **Operator data lives only in `private/`, never in the repository.** This
   repository is public and shared by every operator who clones it. Anything
   that belongs to one operator goes under `private/` in their own clone,
   which is git-ignored as a whole and is never committed, pushed, pasted
   into chat, an issue, a spec or a screenshot:
   - `private/secrets/`: keys and server address read by the render scripts
     (file list and generation commands in `spec/06-operations.md`);
   - `private/notes.md`: names, e-mail addresses, server IP and provider,
     other tenants on the server, the client machines' hardware, OS build,
     home network, installed apps, migrations, anything personal;
   - `private/backups/`: local backups (config copies, git bundles);
   - `private/README.md`: what this operator keeps where.
   Create the folder on first use (`mkdir -p private && chmod 700 private`).
   Tracked files say "the operator" and point to `private/notes.md` for the
   specifics. Before every commit, check the staged diff for operator data;
   if any slipped in, stop and remove it before the commit, not after.
   Rendered configs (`*/sing-box/config.json`) and downloaded binaries
   (`client-linux/bin/`) are build outputs: also git-ignored, regenerated
   from `private/secrets/`. Server access is by SSH key only; a password is
   never used, never typed into chat.
5. **Known manual revert.** Every change to a client machine (launchd/systemd,
   TUN, DNS, pf) ships with a tested one-command revert, documented in
   `spec/06-operations.md`, before it is enabled. No global routing change
   without: persistent process + automatic fail-safe + known manual revert.
6. **English** in code, configs, UI, menu bar text, notifications, logs,
   commit messages and every file in this repo. Chat is in the operator's
   language.
7. **Docs stay current.** After every change (code, config, server state,
   decision), update in the same step: the relevant numbered spec for the how,
   `decisions.md` for the why, `history.md` for what happened and when
   (absolute dates), `spec/todo.md` for what is still open, and the operator
   manual whenever a command, path, state or procedure the operator uses
   changed (`MANUAL.md`, and `README.md` when setup or behaviour changed).
   A change without these updates is not done.
8. **Division of work.** Agents write and run scripts; the operator does GUI
   steps (OS permission dialogs, SwiftBar or GNOME extension prompts), types
   sudo passwords, and makes decisions. Research agents are a cheaper model.
   Never ask the operator to type a secret into chat.
9. **No code without permission.** Writing or changing code, configs,
   scripts, launchd/systemd/pf/docker state, or running anything on the
   server waits for the operator's direct go-ahead for that step in chat.
   Specs and docs do not.
10. **Third parties stay off the tunnel.** Only Anthropic-owned domains
   (`spec/02` Section A) are tunnelled. GitHub, npm, Cloudflare, Google,
   Datadog and similar have their own infrastructure and go direct, even when
   an Anthropic product talks to them. Never add them to the tunnel rules.
11. **Server location: United States, always.** This server and any
   replacement must have a public IP whose geolocation is the USA (checked
   against at least two IP-geolocation services, result and date recorded in
   `private/notes.md`). A server anywhere else is not acceptable for this
   project.
12. **Never cut the agent's own line.** The agent's own session may reach
   Anthropic through this tunnel. Before any change on a client machine that
   can interrupt it (restarting sing-box, changing resolver files or resolved
   links, pf, launchd/systemd), write the one-line revert first, keep the gap
   to seconds, and never stop the server stack while a client depends on it
   unless the operator asked for that test. SSH to the server goes direct and
   must stay that way.
13. **No destructive action without confirmation**: deleting containers,
   volumes, keys, launchd/systemd jobs, pf rules, or anything on the server
   outside this stack.

## Where things are

- `README.md`                what this is, requirements, quick start for a new operator
- `spec/00-overview.md`      goals, scope, threat model, status
- `spec/01-architecture.md`  components and data flow
- `spec/02-domains.md`       the Anthropic domain list (source of truth for rules)
- `spec/03-server.md`        Docker stack, WireGuard + VLESS/Reality, pre-flight findings
- `spec/04-client-macos.md`  sing-box TUN, DNS (resolver files), launchd, scripts
- `spec/05-menubar.md`       SwiftBar indicator: states, colours, menu, icon
- `spec/06-operations.md`    secrets list, start/stop/revert, tests T1–T10
- `spec/07-stack.md`         languages, tools and versions used (approved stack)
- `spec/08-client-linux.md`  Linux client: systemd, resolved DNS layer, Argos, container test
- `client-linux/README.md`   runbook for the agent on the Linux machine: pre-flight, install, tests L1–L12, report-back. **If you are running on Linux, read it right after this file.**
- `spec/decisions.md`        decision log (ADR style)
- `spec/history.md`          dated log of what was done
- `spec/todo.md`             open tasks (optional layers, pending tests)
- `private/`                  this operator's data: secrets/, notes.md, backups/ (git-ignored as a whole; rule 4)
- `MANUAL.md`                operator manual: every command, troubleshooting, server operations

## Tooling notes

- Server access: `ssh` with the key named in `private/secrets/server.env` (user, host,
  port, key path). Never hard-code the IP in committed files.
- Repo path: scripts find the repo relative to themselves; docs write `<repo>`
  for wherever the operator cloned it.

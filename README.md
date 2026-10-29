# anthropic-tunnel

Route every connection to Anthropic and Claude through your own server, and
block it when that server is unreachable. Everything else on the machine is
left alone.

anthropic-tunnel is a self-hosted, split, **fail-closed** tunnel. On your Mac
or Linux machine it captures all traffic to Anthropic's domains (claude.ai,
api.anthropic.com, the Claude desktop app, Claude Code, the Chrome extension,
sign-in, updates, telemetry) and sends it through a WireGuard or VLESS+Reality
tunnel to a small server you run. GitHub, npm, Google, your company VPN and
the rest of the internet keep going direct. If the tunnel is down, Anthropic
traffic is refused instead of leaking out over your normal connection.

It is built with [sing-box](https://sing-box.sagernet.org/) on both ends,
plain shell scripts, launchd or systemd, and a small Python menu bar
indicator. The Linux tray uses GTK/AppIndicator bindings; imported XHTTP
profiles optionally use a local Xray helper.

## Contents

- [Why use it](#why-use-it)
- [How it works](#how-it-works)
- [What goes through the tunnel](#what-goes-through-the-tunnel)
- [Platform status](#platform-status)
- [Requirements](#requirements)
- [Setup](#setup)
- [Daily use](#daily-use)
- [Turning it off, reverting, uninstalling](#turning-it-off-reverting-uninstalling)
- [Limitations](#limitations)
- [Your data stays in `private/`](#your-data-stays-in-private)
- [Working with an AI agent](#working-with-an-ai-agent)
- [Repository layout](#repository-layout)
- [Documentation](#documentation)
- [License](#license)

## Why use it

- **One known exit for all Anthropic services.** Every Claude product on the
  machine reaches Anthropic from your server's IP address, whichever network
  you are on.
- **Only Anthropic traffic is touched.** A full VPN would also move your
  browsing, downloads and work traffic onto the server. Here only six
  Anthropic domains are routed; the rest of the machine behaves as before.
- **No silent fallback.** Typical VPN clients send traffic direct when the
  tunnel drops. This project does the opposite: when the tunnel fails,
  Anthropic hosts stop resolving and stop connecting, so nothing goes out
  over your normal connection by accident.
- **Two transports.** WireGuard is the fast default. VLESS with Reality runs
  over TCP and looks like ordinary TLS, for networks that block or degrade
  WireGuard. You switch between them from the menu bar.
- **Visible.** A menu bar item shows at a glance whether the tunnel is idle,
  carrying Anthropic traffic, down (traffic blocked) or switched off on
  purpose.

## How it works

```
 Your machine                                          Your server (Docker)
 ┌──────────────────────────────────────────┐          ┌──────────────────────────┐
 │ apps: browser, Claude app, claude CLI,   │          │ sing-box                 │
 │       MCP servers, SDK scripts, curl ... │          │  in:  WireGuard  UDP     │
 │            │                             │ WireGuard│  in:  VLESS+Reality TCP  │
 │            │ DNS for Anthropic domains   │ ───────► │            │             │
 │            ▼                             │   or     │            ▼             │
 │  sing-box TUN (root service)             │  VLESS   │  out: direct to          │
 │   - fake IP for Anthropic names          │ ───────► │       api.anthropic.com, │
 │   - route Anthropic names, IP ranges,    │          │       claude.ai, ...     │
 │     sniffed TLS SNI -> selector          │          └──────────────────────────┘
 │   - selector = [WireGuard, VLESS]        │
 │     (no "direct" member: fail-closed)    │
 │   - everything else -> direct            │
 │  DNS layer that exists without sing-box  │
 │   (macOS /etc/resolver files, or Linux   │
 │    systemd-resolved routing domains)     │
 │  menu bar indicator (reads local API)    │
 └──────────────────────────────────────────┘
```

A request to `api.anthropic.com` goes like this:

1. The app asks the system resolver. A per-domain rule sends the question
   for the six Anthropic domains to sing-box only. sing-box answers with a
   fake address from `198.18.0.0/15`.
2. The app connects to that fake address. The packet enters the TUN
   interface; sing-box maps it back to the name and routes it to the
   `anthropic` selector, which holds only the two tunnel transports.
3. sing-box resolves the real address through the tunnel and opens the
   connection from the server. The server just forwards it.

Three things keep it fail-closed:

- **The selector has no direct path.** If the chosen transport is down, the
  connection times out. There is nowhere else for it to go.
- **The DNS layer outlives the daemon.** On macOS six files in
  `/etc/resolver/` point the Anthropic domains at the TUN's DNS address. On
  Linux a permanent dummy link carries systemd-resolved routing domains for
  the same six names. When sing-box is not running, those names do not
  resolve at all, and old fake addresses have no route.
- **Leak guard (macOS).** A packet filter (pf) refuses every packet to an
  Anthropic address unless it leaves through the tunnel interface. It holds
  when sing-box is down, when another VPN takes the routes, and when an app
  resolves names itself and connects to a real IP. A root job re-checks it
  every 5 seconds and keeps the address list current through the tunnel.
- **Belt and braces.** Inside the tunnel, a connection to a real Anthropic
  IP is still recognised by Anthropic's published IP ranges or by the TLS
  server name sniffed from the connection.

The server side is one Docker container, bound to one UDP and one TCP port,
that forwards whatever the client sends. It does no domain filtering of its
own because the client only ever sends Anthropic traffic. Removing it is one
`docker compose down -v`.

Details: [`spec/01-architecture.md`](spec/01-architecture.md).

## What goes through the tunnel

All subdomains of these six Anthropic-owned domains, taken from Anthropic's
own network documentation:

```
anthropic.com   claude.ai   claude.com   claude.app   claudeusercontent.com   claudemcpcontent.com
```

plus Anthropic's published IP ranges (`160.79.104.0/23`, `2607:6bc0::/48`).

Third parties that Anthropic products also contact (GitHub, npm, Google
storage, Cloudflare CDNs, Datadog telemetry) are **not** tunnelled on
purpose: they are not Anthropic servers. The full list with sources, and the
reasoning, is in [`spec/02-domains.md`](spec/02-domains.md).

## Platform status

| Part | Status |
|---|---|
| Server (Docker, any Linux VPS) | in daily use |
| macOS client + SwiftBar indicator | in daily use; acceptance tests T1 to T10 passed ([`spec/06`](spec/06-operations.md)) |
| Linux client + native Wayland GTK/AppIndicator tray | VLESS, imported profiles, DNS routing and tray verified on a real workstation; crash/reboot and login-autostart checks remain open ([`spec/08`](spec/08-client-linux.md)) |

Open work is tracked in [`spec/todo.md`](spec/todo.md).

## Requirements

**Server**
- A Linux VPS with Docker and Docker Compose, root SSH access by key.
- One free UDP port (WireGuard, `51820` in the templates) and one free TCP
  port (VLESS, `8444`).
- This project's own rule is that the server's public IP geolocates to the
  United States, checked on two geolocation services
  ([`CLAUDE.md`](CLAUDE.md) rule 11). Adjust it if you fork the project for
  another purpose.

**macOS client**
- Homebrew, `sing-box` (tested with 1.14.4; the server image is pinned to the
  same version), `python3`.
- [SwiftBar](https://github.com/swiftbar/SwiftBar) 2.1.1 or later for the
  indicator (optional).
- An admin account (install needs `sudo` once).

**Linux client**
- systemd and systemd-resolved (the default on Ubuntu Desktop and Server),
  iproute2, `python3`, `curl` or `wget`, `sudo`.
- For the optional tray: GTK 3, Python GI and Ayatana AppIndicator3 (or
  AppIndicator3), plus a StatusNotifier host such as Ubuntu AppIndicators.

**Where you prepare things:** the machine that holds `private/secrets/` (usually your
Mac) also needs `sing-box` to generate keys and validate configs.

Pinned versions and why each tool was chosen:
[`spec/07-stack.md`](spec/07-stack.md).

## Setup

All commands run from the repository folder unless stated otherwise.

### 1. Clone

```bash
git clone https://github.com/danialrp/anthropic-tunnel.git
cd anthropic-tunnel
```

### 2. Create your secrets

Everything that belongs to you (keys, server address, notes, backups) lives
in `private/`, a folder that is git-ignored as a whole and never leaves your
machine. Keys go in `private/secrets/`. Generate everything once:

```bash
mkdir -p private/secrets && chmod 700 private private/secrets && cd private/secrets
umask 077
for n in wg-server wg-client wg-linux; do
  k=$(sing-box generate wg-keypair)
  echo "$k" | awk '/PrivateKey/{print $2}' > "$n.key"
  echo "$k" | awk '/PublicKey/{print $2}'  > "$n.pub"
done
k=$(sing-box generate reality-keypair)
echo "$k" | awk '/PrivateKey/{print $2}' > reality.key
echo "$k" | awk '/PublicKey/{print $2}'  > reality.pub
sing-box generate rand --base64 32 > wg-psk.key
sing-box generate uuid             > vless-uuid
sing-box generate rand --hex 4     > reality-shortid
sing-box generate rand --hex 16    > clash-api.secret
cp ../../server/.env.example server.env
cd ../..
```

Then edit `private/secrets/server.env` and fill in `SERVER_IP`, `SSH_USER`,
`SSH_PORT` and `SSH_KEY` (path to your private key).

Each client gets its own WireGuard key pair (`wg-client` for the Mac,
`wg-linux` for Linux); a WireGuard peer is a single session, so two machines
must never share one. VLESS uses one UUID for all clients. The table of all
files and what each one is for: [`spec/06-operations.md`](spec/06-operations.md#secrets).

Keep your own notes (server provider, IP, which machine is which) in
`private/notes.md`. Nothing personal goes into tracked files; see
[Your data stays in `private/`](#your-data-stays-in-private).

### 3. Server

Check the server first, read-only, and make sure the two ports are free and
the tunnel subnet `10.66.66.0/24` does not clash with anything:

```bash
. private/secrets/server.env
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" 'docker --version; docker compose version; ss -lunp | grep -E ":51820\b" ; ss -ltnp | grep -E ":8444\b"; ip -br addr'
```

Empty output for the two `ss` lines means the ports are free. The full
pre-flight list and what to look for is in
[`spec/03-server.md`](spec/03-server.md).

Render the server config and deploy:

```bash
sh server/render.sh
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" 'mkdir -p /opt/anthropic-tunnel/sing-box'
scp -i "$SSH_KEY" -P "$SSH_PORT" server/docker-compose.yml "$SSH_USER@$SERVER_IP:/opt/anthropic-tunnel/"
scp -i "$SSH_KEY" -P "$SSH_PORT" server/sing-box/config.json "$SSH_USER@$SERVER_IP:/opt/anthropic-tunnel/sing-box/config.json"
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" 'chmod 600 /opt/anthropic-tunnel/sing-box/config.json; cd /opt/anthropic-tunnel && docker compose up -d && sleep 3 && docker compose logs --tail 20'
```

The log should end with `sing-box started`. The container runs with
`network_mode: host`, binds only the two ports, adds no firewall rules and
touches nothing else on the host; [`spec/03`](spec/03-server.md) explains
why host networking was chosen.

### 4. macOS client

```bash
brew install sing-box
bash client/render.sh                    # builds client/sing-box/config.json and validates it
sudo bash client/scripts/install.sh      # installs and starts the service
```

`install.sh` copies the sing-box binary to `/usr/local/anthropic-tunnel/`,
installs the rendered config, loads the launchd daemon
`local.anthropic-tunnel` (starts at boot, restarts on crash), writes the six
`/etc/resolver` files, and adds a sudoers entry so your user can run the
connect, disconnect and restart scripts without a password. It then
installs the leak guard (pf rules plus two root jobs), runs a self-test that
removes the guard again if Anthropic stops answering through the tunnel, and
prints the status. Healthy output:

```
daemon loaded : yes
process       : running
resolver files: 6/6
tun interface : up
claude.ai ->  198.18.0.2      fake IP: the name was answered by the tunnel
api check     : 401           Anthropic answered through the tunnel (401 = no API key, expected)
```

The full installed layout is in [`spec/04-client-macos.md`](spec/04-client-macos.md).

**Menu bar indicator (optional):**

```bash
brew install --cask swiftbar
open -a SwiftBar                         # first launch: choose a plugin folder
bash menubar/install.sh
```

### 5. Linux client

Render the Linux config on the machine that holds `private/secrets/`:

```bash
bash client-linux/render.sh
```

Clone the repository on the Linux machine and copy the rendered file
`client-linux/sing-box/config.json` to the same path there. It contains keys,
so move it with `scp` or another private channel. Then, on Linux:

```bash
sudo bash client-linux/scripts/install.sh
```

The script downloads the official sing-box 1.14.4 release for your
architecture, checks its pinned SHA-256, installs two systemd units
(`anthropic-tunnel-dns` for the DNS layer, `anthropic-tunnel` for sing-box),
marks its two network interfaces unmanaged for NetworkManager, adds the
sudoers entry and prints the status. Healthy output matches the macOS one,
with `dns layer : up (6/6 routing domains)` instead of resolver files.

For VLESS-only setup before deploying a separate Linux WireGuard peer, render
with `bash client-linux/render.sh --vless-only`. Additional profiles and
per-machine options live in `private/secrets/`; see the operator manual.

Install the optional Wayland tray with `bash menubar/install-linux.sh`. It
starts immediately and at desktop login. Exact steps, a twelve-point test
list and known pitfalls are in the Linux runbook
[`client-linux/README.md`](client-linux/README.md).

### 6. Verify

On the client:

```bash
curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code} remote_ip=%{remote_ip}\n" https://api.anthropic.com/v1/models
```

Expect `HTTP 401` and a `remote_ip` starting with `198.18.`. Then open
https://claude.ai in a browser. To see the kill switch work, stop the
service for a moment (`sudo launchctl kill SIGTERM system/local.anthropic-tunnel`
on macOS, or `sudo systemctl stop anthropic-tunnel` on Linux): Anthropic sites
stop loading while everything else keeps working, and the service comes back
by itself on macOS (start it again on Linux). The complete acceptance tests
are T1 to T10 in [`spec/06-operations.md`](spec/06-operations.md) and L1 to
L12 in the Linux runbook.

## Daily use

The same scripts exist on both platforms, installed under
`/usr/local/anthropic-tunnel/bin/`:

| Task | Command |
|---|---|
| Status | `bash /usr/local/anthropic-tunnel/bin/status.sh` |
| Switch off on purpose (Anthropic then goes direct, knowingly) | `sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh` |
| Switch on | `sudo /usr/local/anthropic-tunnel/bin/tunnel-up.sh` |
| Restart the service | `sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh` |
| Live log, macOS | `tail -f /var/log/anthropic-tunnel/sing-box.log` |
| Live log, Linux | `journalctl -fu anthropic-tunnel` |
| Use VLESS instead of WireGuard | `curl -s -X PUT -H "Authorization: Bearer $(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)" -d '{"name":"vless-out"}' http://127.0.0.1:9090/proxies/anthropic` (use `wg-out` to go back) |

The three `sudo` commands run without a password thanks to the sudoers
entry; the indicator calls the same scripts.

**Indicator states**

| Colour | Title | Meaning |
|---|---|---|
| green | `✓` | connected, idle |
| blue | `↓25K` | connected, Anthropic traffic in the last 10 seconds |
| red | `DOWN` | tunnel unreachable, Anthropic traffic is blocked |
| grey | `OFF` | switched off on purpose, Anthropic goes direct |
| grey | `?` | service starting or local API not answering |
| red | `GUARD` | macOS: tunnel on but the leak guard is not active |
| red | `PROXY` | macOS: a system proxy or transparent-proxy extension could carry Anthropic traffic around the tunnel |

Red appears only after two failed probes in a row, so a short network hiccup
does not flash red. The menu has the status line with latency and uptime,
connect, disconnect and restart, the transport switch, live statistics,
diagnostics and the log.

Every command, troubleshooting steps and server operations:
[`MANUAL.md`](MANUAL.md).

## Turning it off, reverting, uninstalling

- **Off for a while:** `sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh`.
  The service stops and the DNS layer and leak guard are removed; Anthropic
  traffic goes direct until `tunnel-up.sh`.
- **Only the leak guard off, macOS:** `sudo bash /usr/local/anthropic-tunnel/bin/guard-off.sh`.
- **If the scripts themselves are broken, macOS:**
  ```bash
  sudo launchctl bootout system/local.anthropic-tunnel
  sudo rm -f /etc/resolver/anthropic.com /etc/resolver/claude.ai /etc/resolver/claude.com /etc/resolver/claude.app /etc/resolver/claudeusercontent.com /etc/resolver/claudemcpcontent.com
  ```
- **If the scripts themselves are broken, Linux:**
  ```bash
  sudo systemctl disable --now anthropic-tunnel anthropic-tunnel-dns; sudo resolvectl revert anthropic-dns0; sudo ip link del anthropic-dns0
  ```
- **Uninstall a client:** `sudo bash client/scripts/uninstall.sh` (macOS) or
  `sudo bash client-linux/scripts/uninstall.sh` (Linux). Every file, service,
  sudoers entry and DNS setting the installer created is removed.
- **Remove the server stack:**
  ```bash
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP" 'cd /opt/anthropic-tunnel && docker compose down -v && cd / && rm -rf /opt/anthropic-tunnel'
  ```

## Limitations

- **Another VPN at the same time.** On macOS the leak guard refuses
  Anthropic traffic that does not leave through this tunnel, so another VPN
  cannot carry it; Anthropic stops working until that VPN releases the
  routes. System proxies and transparent-proxy extensions work above the
  packet layer and cannot be filtered; the indicator turns red (`PROXY`)
  when one is on.
- **Shared CDN hosts.** Anthropic hosts behind a shared CDN (for example the
  status page) are routed through the tunnel by name, but the leak guard
  does not block their addresses, because unrelated sites share them.
- **Encrypted DNS plus Encrypted Client Hello.** An app that uses its own
  encrypted DNS and hides the TLS server name shows neither a name to fake
  nor a name to sniff. Only the IP-range rule catches it.
- **Linux acceptance checks.** Real-machine VLESS, profile probes, DNS routing
  and the Wayland tray have been verified. Crash/reboot, NetworkManager
  persistence and tray startup at login still need real-host testing.
- **DNS protection scope.** The persistent DNS layer protects the configured
  suffixes during daemon failure; it is not a complete firewall kill switch
  for cached real IPs or applications that bypass the system resolver.
- **sing-box version.** Tested with 1.14.4 on all three ends. Homebrew may
  install a newer version; keep the server image tag in
  `server/docker-compose.yml` on the same version.
- **Your responsibility.** Use the project in line with Anthropic's terms of
  service and the rules that apply where you are.

## Your data stays in `private/`

The repository is public and identical for everyone who clones it. Each
operator keeps their own data in `private/` inside their clone. Git ignores
that folder completely, so it can never be committed or pushed by accident.

```
private/
  secrets/     keys and server address (the render scripts read them here)
  notes.md     your server, your machines, your network, anything personal
  backups/     local backups
  README.md    what you keep where
```

Tracked files never name an operator, a server, an IP address or a machine;
they say "the operator" and point to `private/notes.md`. The rule is binding
for people and agents alike ([`CLAUDE.md`](CLAUDE.md) rule 4). Rendered
configs and downloaded binaries are git-ignored build outputs, recreated from
`private/secrets/`.

## Working with an AI agent

The project was built by a person working with an AI coding agent, and it is
set up so that the next operator can do the same.

- Start the agent in the repository and tell it to read
  [`CLAUDE.md`](CLAUDE.md). That file holds the rules (Rule 0: no Anthropic
  traffic ever goes direct; no changes without the operator's go-ahead; a
  tested revert before any change to a client; never break the agent's own
  connection) and a map of every spec.
- On a Linux machine the agent follows
  [`client-linux/README.md`](client-linux/README.md) step by step.
- Keep anything personal (your name, e-mail, server provider and IP,
  hardware, home network) in `private/notes.md`. Agents on your machine read
  it there; nothing outside your machine sees it. Tracked files only ever say
  "the operator".
- Every change updates the matching spec, the decision log
  ([`spec/decisions.md`](spec/decisions.md)), the dated history
  ([`spec/history.md`](spec/history.md)) and the open-task list, so the
  repository always explains itself.

## Repository layout

```
README.md            this file
MANUAL.md            operator manual: every command, troubleshooting, server operations
CLAUDE.md            rules for AI agents (read first when working with one)
LICENSE              MIT
spec/                numbered specs, decision log, history, open tasks
server/              docker-compose.yml, sing-box config template, render.sh
client/              macOS: config template, render.sh, launchd plist, scripts/
client-linux/        Linux: config template, render.sh, systemd/, scripts/, runbook
menubar/             indicator plugin (SwiftBar on macOS, GTK/AppIndicator on Linux), installers, icon generator
tests/               test notes; linux-container/ runs the Linux client in a systemd container
private/             your data: secrets/, notes.md, backups/ (git-ignored as a whole, you create it)
```

## Documentation

| Document | What is in it |
|---|---|
| [`MANUAL.md`](MANUAL.md) | daily commands, troubleshooting, install and update, server operations |
| [`client-linux/README.md`](client-linux/README.md) | Linux runbook: pre-flight, install, tests L1 to L12, pitfalls |
| [`spec/00-overview.md`](spec/00-overview.md) | goals, scope, threat and failure model |
| [`spec/01-architecture.md`](spec/01-architecture.md) | components and data flow |
| [`spec/02-domains.md`](spec/02-domains.md) | Anthropic domains with sources; what is deliberately not tunnelled |
| [`spec/03-server.md`](spec/03-server.md) | server stack, pre-flight, deployment notes |
| [`spec/04-client-macos.md`](spec/04-client-macos.md) | macOS client: config, DNS layer, launchd, installed layout |
| [`spec/05-menubar.md`](spec/05-menubar.md) | indicator states, colours, menu |
| [`spec/06-operations.md`](spec/06-operations.md) | secrets, setup order, tests T1 to T10, reverts |
| [`spec/07-stack.md`](spec/07-stack.md) | tools, versions, and why |
| [`spec/08-client-linux.md`](spec/08-client-linux.md) | Linux client design and container test results |
| [`spec/decisions.md`](spec/decisions.md) | every design decision with its reason and the rejected options |

## License

MIT, see [`LICENSE`](LICENSE).

This project is not affiliated with or endorsed by Anthropic. "Anthropic" and
"Claude" are trademarks of Anthropic, PBC.

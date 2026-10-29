# anthropic-tunnel operator manual

Everything you need after setup: what the indicator means, every daily
command on macOS and Linux, troubleshooting, updates, server operations and
secrets. For what the project is and the first installation, read
[`README.md`](README.md). Design details live in [`spec/`](spec/).

Commands that start with `sudo` ask for your password unless they are one of
the three control scripts (`tunnel-up.sh`, `tunnel-down.sh`,
`tunnel-restart.sh`), which the installer allows without a password.

## 1. What runs where

| Where | What | Notes |
|---|---|---|
| Server | Docker container `anthropic-tunnel-sing-box` under `/opt/anthropic-tunnel/` | binds one UDP port (WireGuard) and one TCP port (VLESS); touches nothing else on the host |
| macOS | launchd daemon `local.anthropic-tunnel` (sing-box in TUN mode, root) | starts at boot before login; restarted within a second if it dies |
| macOS | six files in `/etc/resolver/` | send the Anthropic domains to the tunnel's DNS; without the daemon these names do not resolve |
| Linux | systemd units `anthropic-tunnel` (sing-box) and `anthropic-tunnel-dns` (DNS layer) | start at boot; `Restart=always` |
| Linux | dummy link `anthropic-dns0` with systemd-resolved routing domains | the Linux counterpart of the resolver files |
| Both | menu bar indicator (SwiftBar on macOS, Argos on GNOME) | status, statistics, connect and disconnect, transport switch |

Two transports: **WireGuard** (`wg-out`, default, UDP) and **VLESS+Reality**
(`vless-out`, TCP) for networks that block WireGuard.

## 2. The indicator

Icon: three concentric circles, coloured by state, with a short title.

| Colour | Title | Meaning | What to do |
|---|---|---|---|
| green | `✓` | connected, idle; latency is in the menu's status line | nothing |
| blue | `↓25K`, `↑3K` or `↓0` | connected and Anthropic traffic moved in the last 10 seconds; the title is the current rate (`↓0`: nothing in this 5-second tick, still inside the active window) | nothing |
| red | `DOWN` | tunnel unreachable; Anthropic traffic is blocked (kill switch) | see [Troubleshooting](#4-troubleshooting) |
| grey | `OFF` | switched off on purpose; Anthropic goes **direct** | Connect when you want it back |
| grey | `?` | service restarting or the local API not answering | wait a few seconds |
| green or blue with `·` | `·` | one probe failed, not yet red | wait for the next probe |

Red needs two failed probes in a row, so a short network hiccup does not
flash red. The probe is a real request to `api.anthropic.com` through the
tunnel, so green means "Anthropic answers through the tunnel", not only
"the WireGuard handshake works".

**Menu** (click the icon):

- Status line, for example `Connected via wg-out · 640 ms · up 3h 12m`.
- **Connect** (enabled only when off), **Disconnect** and **Restart tunnel**
  (enabled only when on).
- **Transport**: `wg-out` or `vless-out`, the active one marked. The choice
  survives restarts.
- **Stats**: session upload and download, current rate, the Anthropic hosts
  with open connections and their volume.
- **Anthropic via tunnel: yes/no**, and in the red state **Server reachable
  (tcp/22): yes/no**, which tells a server or network problem apart from an
  Anthropic-side one.
- **Open log** (Console on macOS, a terminal with `journalctl` on Linux),
  **Copy diagnostics** (a full text report on the clipboard, handy to paste
  to an agent), **Flush DNS cache**.

A notification appears only when the state changes (down, up, off, on).

## 3. Daily commands

### macOS and Linux

| Task | Command |
|---|---|
| Status (six checks) | `bash /usr/local/anthropic-tunnel/bin/status.sh` |
| Switch off on purpose (grey; Anthropic goes direct) | `sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh` |
| Switch on | `sudo /usr/local/anthropic-tunnel/bin/tunnel-up.sh` |
| Restart the service | `sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh` |

Healthy status on macOS:

```
daemon loaded : yes
process       : running
resolver files: 6/6
tun interface : up
claude.ai ->  198.18.0.2      fake IP: answered by the tunnel's DNS
api check     : 401           Anthropic reached through the tunnel (no API key, so 401)
```

On Linux the first lines read `daemon enabled`, `process` and
`dns layer : up (6/6 routing domains)`.

Check that a request really goes through the tunnel (expect `401` and a
`remote_ip` in `198.18.0.0/15`):

```bash
curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code} remote_ip=%{remote_ip}\n" https://api.anthropic.com/v1/models
```

Switch transport from a terminal instead of the menu (write `wg-out` to go
back):

```bash
curl -s -X PUT -H "Authorization: Bearer $(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)" -d '{"name":"vless-out"}' http://127.0.0.1:9090/proxies/anthropic
```

List current Anthropic connections and the transport each one uses:

```bash
curl -s -H "Authorization: Bearer $(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)" http://127.0.0.1:9090/connections | python3 -c "import sys,json; d=json.load(sys.stdin); [print((c['metadata'].get('host') or c['metadata'].get('destinationIP')), '->', c['chains']) for c in d['connections'] if 'anthropic' in c['chains']]"
```

### macOS only

| Task | Command |
|---|---|
| Live log | `tail -f /var/log/anthropic-tunnel/sing-box.log` |
| Does an Anthropic name get a fake IP? (expect `198.18.x.x`) | `dscacheutil -q host -a name claude.ai` |

`dig` ignores `/etc/resolver` and always shows the real address, so it is
not a valid test on macOS. Use `dscacheutil`.

### Linux only

| Task | Command |
|---|---|
| Live log | `journalctl -fu anthropic-tunnel` |
| Does an Anthropic name get a fake IP? (expect `198.18.x.x -- link: anthropic-dns0`) | `resolvectl query claude.ai` |
| DNS layer detail | `resolvectl status anthropic-dns0` |
| Service state | `systemctl status anthropic-tunnel anthropic-tunnel-dns` |

## 4. Troubleshooting

### Red (`DOWN`)

1. Open the menu. **Server reachable: no** means the path from you to the
   server is the problem: your connection, a network that blocks the
   transport, or the server is down.
2. Switch **Transport** to the other one. Some networks block only
   WireGuard; VLESS runs over TCP and looks like ordinary TLS.
3. If both transports stay red, check the server ([section 6](#6-server)).
4. **Server reachable: yes** but **Anthropic via tunnel: no** means the
   server cannot reach Anthropic, or Anthropic itself has a problem. Check
   https://status.claude.com (through the tunnel it may also fail) and wait.

### Grey `?` for more than a few seconds

```bash
bash /usr/local/anthropic-tunnel/bin/status.sh
tail -20 /var/log/anthropic-tunnel/sing-box.log      # macOS
journalctl -u anthropic-tunnel -n 20 --no-pager      # Linux
```

If `process: not running` stays, run `tunnel-restart.sh`. A config error
appears in the log where `sing-box started` would normally be.

### The icon is not in the menu bar

- Is SwiftBar running? `open -a SwiftBar`. On GNOME, is Argos enabled?
  `gnome-extensions info argos@pew.worldwidemann.com`.
- On a crowded macOS menu bar, items that do not fit are hidden, not moved.
  Remove or shorten other items. The tunnel item is narrow on purpose (only
  `✓` when idle).
- Is the plugin in place? It is in SwiftBar's plugin folder (shown in
  SwiftBar's preferences) or `~/.config/argos/` on Linux, named
  `anthropic-tunnel.5s.py`.
- Run the plugin by hand to see an error: `<plugin folder>/anthropic-tunnel.5s.py | head -3`.

### No Anthropic site loads, everything else works

That is the kill switch working: the tunnel is down (red) or the service is
not running. If you need Anthropic urgently without the tunnel, for example
while the server is broken:

```bash
sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh
```

This sends Anthropic traffic direct, knowingly. Go back with `tunnel-up.sh`.

### Another VPN is running

Any other VPN or proxy client that takes the default route and DNS can send
Anthropic traffic around the tunnel. Do not run one at the same time. If
you need it: `tunnel-down.sh`, use the other VPN, then `tunnel-up.sh`.

### After changing networks

The tunnel normally stays up. If it turns red, switch transport or run
`tunnel-restart.sh`.

### Linux: non-Anthropic names stopped resolving

sing-box answers all port-53 traffic on Linux and needs systemd-resolved to
know the upstream DNS per network link (DHCP provides this). Check with
`resolvectl dns`: the physical link must list a server. If only "Global"
has one, see [`spec/08-client-linux.md`](spec/08-client-linux.md).

### Emergency revert when the scripts themselves are broken

macOS:

```bash
sudo launchctl bootout system/local.anthropic-tunnel
sudo rm -f /etc/resolver/anthropic.com /etc/resolver/claude.ai /etc/resolver/claude.com /etc/resolver/claude.app /etc/resolver/claudeusercontent.com /etc/resolver/claudemcpcontent.com
```

Linux:

```bash
sudo systemctl disable --now anthropic-tunnel anthropic-tunnel-dns; sudo resolvectl revert anthropic-dns0; sudo ip link del anthropic-dns0
```

After either, the machine behaves as before installation (Anthropic direct).

## 5. Install, update, remove

All from the repository folder.

### macOS

| Task | Command |
|---|---|
| Render the client config from the template and `private/secrets/` (no sudo; runs `sing-box check`) | `bash client/render.sh` |
| Install or update everything (binary, config, scripts, launchd, sudoers, resolver files; restarts the service) | `sudo bash client/scripts/install.sh` |
| Apply a new config only | `sudo install -o root -g wheel -m 600 client/sing-box/config.json /usr/local/anthropic-tunnel/etc/config.json && sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh` |
| Update sing-box | `brew upgrade sing-box && sudo bash client/scripts/install.sh` (keep the server image on the same version) |
| Install or update the indicator (no sudo) | `bash menubar/install.sh` |
| Remove everything (service, plist, sudoers, resolver files, install folder, logs; Homebrew's sing-box stays) | `sudo bash client/scripts/uninstall.sh` |

Installed paths:

| Path | What |
|---|---|
| `/usr/local/anthropic-tunnel/bin/` | sing-box binary and the scripts (root) |
| `/usr/local/anthropic-tunnel/etc/config.json` | rendered config with keys (mode 600) |
| `/usr/local/anthropic-tunnel/etc/clash-api.secret`, `server-ip` | read by the indicator (mode 640, your group) |
| `/usr/local/anthropic-tunnel/var/cache.db` | fake-IP cache and the chosen transport |
| `/var/log/anthropic-tunnel/sing-box.log` | service log |
| `/Library/LaunchDaemons/local.anthropic-tunnel.plist` | service definition |
| `/etc/sudoers.d/anthropic-tunnel` | password-free access to the three control scripts |
| `/etc/resolver/<six domains>` | per-domain DNS |
| `<SwiftBar plugin folder>/anthropic-tunnel.5s.py` | indicator |
| `~/Library/Application Support/anthropic-tunnel-menubar/state.json` | indicator state between refreshes |

### Linux

| Task | Command |
|---|---|
| Render the config (on the machine that holds `private/secrets/`), then copy `client-linux/sing-box/config.json` to the Linux clone | `bash client-linux/render.sh` |
| Install or update (downloads the pinned sing-box, checks SHA-256, units, DNS layer, sudoers, NetworkManager setting) | `sudo bash client-linux/scripts/install.sh` |
| Install or update the indicator (GNOME + Argos, no sudo) | `bash menubar/install-linux.sh` |
| Remove everything | `sudo bash client-linux/scripts/uninstall.sh` |

Installed layout and design: [`spec/08-client-linux.md`](spec/08-client-linux.md).
Step-by-step runbook with tests: [`client-linux/README.md`](client-linux/README.md).

Test the Linux client inside a systemd container on any machine with
Docker (`bash tests/linux-container/run.sh`, remove with
`bash tests/linux-container/run.sh clean`). Its limits are listed in spec/08.

## 6. Server

The server address and SSH details are in `private/secrets/server.env` (git-ignored).
Load them in each new terminal, from the repository folder:

```bash
. private/secrets/server.env
alias srv='ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SERVER_IP"'
```

Treat the server as shared: touch only `/opt/anthropic-tunnel/` and this
container. No firewall, sshd, password, package or other-service changes.

| Task | Command |
|---|---|
| Log in | `srv` |
| Container and ports | `srv 'cd /opt/anthropic-tunnel && docker compose ps && ss -lunp \| grep 51820 && ss -ltnp \| grep 8444'` |
| Log | `srv 'cd /opt/anthropic-tunnel && docker compose logs --tail 50'` |
| Restart | `srv 'cd /opt/anthropic-tunnel && docker compose restart'` |
| Check the public IP's country | `curl -s https://ipinfo.io/$SERVER_IP/json \| grep -E '"country"\|"city"'` |
| Remove the stack completely | `srv 'cd /opt/anthropic-tunnel && docker compose down -v && cd / && rm -rf /opt/anthropic-tunnel'` |

Render and deploy a new server config:

```bash
sh server/render.sh && scp -i "$SSH_KEY" -P "$SSH_PORT" server/sing-box/config.json "$SSH_USER@$SERVER_IP:/opt/anthropic-tunnel/sing-box/config.json" && srv 'chmod 600 /opt/anthropic-tunnel/sing-box/config.json; cd /opt/anthropic-tunnel && docker compose restart'
```

Deploy a new compose file (for example a new image version):

```bash
scp -i "$SSH_KEY" -P "$SSH_PORT" server/docker-compose.yml "$SSH_USER@$SERVER_IP:/opt/anthropic-tunnel/docker-compose.yml" && srv 'cd /opt/anthropic-tunnel && docker compose up -d'
```

Worth knowing about the stack (reasons in [`spec/03-server.md`](spec/03-server.md)):

- The container uses `network_mode: host`. On shared hosts a foreign
  `notrack` rule for port 443 can break Docker's bridge NAT; host networking
  needs no NAT and still binds only the two ports.
- Tunnel MTU is 1280, safe for any path; the original server's return path
  measured 1420.
- Reality uses `www.apple.com` as its handshake target.
- The stack adds no firewall rules and never enables one.

## 7. Secrets and other operator data

Everything that belongs to you lives in `private/`, which git ignores as a
whole: `secrets/` for keys, `notes.md` for your server, machines and anything
personal, `backups/` for local backups ([`CLAUDE.md`](CLAUDE.md) rule 4).

`private/secrets/` holds the server address, WireGuard keys
(server, one pair per client, a pre-shared key), the VLESS UUID, the Reality
key pair and short id, and the local API secret. The full table with
generation commands is in
[`spec/06-operations.md`](spec/06-operations.md#secrets);
the one-shot generation block is in [`README.md`](README.md#2-create-your-secrets).

Never paste a value into chat, a spec, an issue or a commit. If one leaks,
generate a new value, re-render server and clients, and deploy both.

## 8. Tests

| # | Test | Expected |
|---|---|---|
| T1 | API request from the client | fake IP, through the tunnel; the server log shows it |
| T2 | claude.ai in a browser | loads through the tunnel |
| T3 | Stop the server container | Anthropic blocked within seconds, everything else fine |
| T4 | Start it again | traffic resumes |
| T5 | `kill -9` the client service | back within about a second |
| T6 | Non-Anthropic traffic | goes direct |
| T7 | `tunnel-down.sh` / `tunnel-up.sh` | grey and direct, then back; no password |
| T8 | `uninstall.sh` | machine exactly as before |
| T9 | Switch WireGuard and VLESS | both carry traffic |
| T10 | Reboot | everything back without manual action |

Procedures and recorded results: [`spec/06-operations.md`](spec/06-operations.md).
The Linux equivalents L1 to L12: [`client-linux/README.md`](client-linux/README.md).
Quick check after any change: `status.sh` and the `curl … remote_ip` line in
[section 3](#3-daily-commands).

## 9. Project rules in short

The binding version is [`CLAUDE.md`](CLAUDE.md).

- Rule 0: all Anthropic traffic goes through the tunnel; if the tunnel is
  down it is blocked, never sent direct.
- Verify, never assume.
- The server may be shared: only this stack is ours.
- Third parties (GitHub, npm, Cloudflare, Google, Datadog) never go through
  the tunnel.
- No change to a client without a tested one-line revert, and no change that
  interrupts the connection for more than seconds.
- Every change updates its spec, the decision log, the history, the open
  tasks and, when a command changed, this manual.
- Personal details stay in the git-ignored `private/notes.md`.

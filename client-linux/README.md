# Linux client runbook (for the agent working on the Ubuntu machine)

You are on the operator's Linux machine (Ubuntu or another systemd +
systemd-resolved distribution) with a clone of this repo. Your job: bring
up the Anthropic tunnel client here with exactly the behaviour the Mac has,
verify it, and write the results back into the repo. Everything you need is
in this file plus the specs it links. Read `CLAUDE.md` first: its rules apply
here unchanged. The ones that bite most on Linux:

- Rule 0: every byte to an Anthropic domain goes through the tunnel; if the
  tunnel is down that traffic is blocked, never sent direct. Never add a
  `direct` member to the `anthropic` selector, never "temporarily" bypass.
- Rule 1: verify, do not assume. Ubuntu Desktop vs Server, NetworkManager vs
  networkd, which DNS the DHCP gave, which GNOME version: check with the
  commands below before acting.
- Rule 9: no code, config or system change without the operator's go-ahead in chat
  for that step. Reading, checking and writing docs is free.
- Rule 12: on this machine the agent's own session may run through this
  tunnel too. Before restarting or stopping the daemon, say what you are
  doing and keep the gap to seconds.
- Rule 7: every change updates `spec/08-client-linux.md`, `spec/history.md`,
  `spec/todo.md` and, if a command the operator uses changed, `MANUAL.md`.
- Chat with the operator in their language; everything in the repo is English.

Design and the reasons behind it: `spec/08-client-linux.md`. Domain list:
`spec/02-domains.md`. Server: `spec/03-server.md`. Operations and the Mac
test matrix: `spec/06-operations.md`.

## 0. What already exists (2026-10-29)

- `client-linux/` passed container tests and a real workstation VLESS/DNS
  setup, imported-profile probes and native Wayland tray checks. Real-host
  crash/reboot, NetworkManager persistence and login autostart remain open;
  see `spec/08-client-linux.md` for the recorded results.
- The server has the Mac's WireGuard peer only. The Linux peer
  (`10.66.66.3/32`, key `private/secrets/wg-linux.key` on the operator's main machine) is in the server
  template but **not deployed** unless `spec/history.md` says it was. Until
  then only the VLESS transport works from here (step 5).
- Render where the operator keeps the necessary client credentials under
  `private/secrets/` (git-ignored). Alternatively transfer only the rendered
  config to Linux over a private channel. Keep machine notes in
  `private/notes.md`; never copy server private keys to a client.

## 1. Pre-flight (read-only)

Run and paste the results into your notes; decide nothing before seeing them.

```bash
cat /etc/os-release | head -3; uname -m; systemctl --version | head -1
systemctl is-active systemd-resolved NetworkManager systemd-networkd 2>&1
readlink -f /etc/resolv.conf; grep -v '^#' /etc/resolv.conf
resolvectl status | head -20          # per-link DNS servers must exist (step 6 explains why)
resolvectl dns                        # which link has the upstream DNS
ip -br addr; ip route | head -5; ip rule
ls -l /dev/net/tun; command -v curl wget python3 ip resolvectl sudo
sudo -n true 2>&1 | head -1          # does sudo need a password (it normally does: the operator types it)
gnome-shell --version 2>/dev/null; echo $XDG_SESSION_TYPE   # Desktop only
ls /etc/sudoers.d/ /etc/systemd/system/anthropic* /usr/local/anthropic-tunnel 2>&1 | head
```

Record in `spec/08-client-linux.md` under a new heading "Real machine
(date)": Ubuntu edition and version, arch, network manager in use, where the
upstream DNS comes from, GNOME version. Put anything personal (hostname,
LAN addresses, ISP) in `private/notes.md` only, which is git-ignored and may
not exist on this machine yet; create it if you need it.

Stop conditions (report to the operator, do not work around):
- `systemd-resolved` not active, or `/etc/resolv.conf` not pointing at
  `127.0.0.53` (stub mode). The DNS layer relies on resolved.
- No `/dev/net/tun`.
- Another VPN/proxy client active (`ip rule`, `ip route` show a foreign
  default route or table). Same rule as on the Mac (spec/06): never two at
  once.

## 2. Render locally or transfer the rendered config

On the machine holding the client credentials:

```bash
cd <repo> && bash client-linux/render.sh
```

Use `bash client-linux/render.sh --vless-only` if no separate Linux WireGuard
peer is deployed; that mode does not require WireGuard keys. When rendering
on another machine, copy `client-linux/sing-box/config.json` into the
same path inside this clone (`scp`, USB, anything; the file holds the
WireGuard private key, the VLESS UUID and the Clash API secret, so it must
not go through chat or a public channel). It is git-ignored here. Check:

```bash
ls -l client-linux/sing-box/config.json && grep -c '__' client-linux/sing-box/config.json   # must print 0
```

## 3. Install (needs the operator's go, then their sudo password)

What `install.sh` changes on this machine, so you can list it before asking:
`/usr/local/anthropic-tunnel/{bin,etc,var}`, two units in
`/etc/systemd/system/` (enabled), `/etc/sudoers.d/anthropic-tunnel` (the
invoking user may run the three up/down/restart scripts without password),
`/etc/NetworkManager/conf.d/anthropic-tunnel.conf` if NetworkManager exists
(marks `anthropic-dns0` and `anthropic-tun0` unmanaged), and the dummy link
`anthropic-dns0`. It downloads `sing-box-1.14.4-linux-<arch>.tar.gz` from the
official GitHub release into `client-linux/bin/` (git-ignored) and verifies
the pinned sha256. Full table: spec/08 "Installed layout".

```bash
sudo bash client-linux/scripts/install.sh
```

It ends with `status.sh`. Healthy output:

```
daemon enabled: yes
process       : running
dns layer     : up (6/6 routing domains)
tun interface : up
claude.ai ->  198.18.x.x
api check     : 401
```

If the dual-transport default selects an undeployed Linux WireGuard peer,
`api check` can be `000`: go to step 5. A VLESS-only render selects VLESS
immediately and should return `401`.

One-line revert, memorise it before step 3:

```bash
sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh
```

If the scripts themselves are broken:

```bash
sudo systemctl disable --now anthropic-tunnel anthropic-tunnel-dns; sudo resolvectl revert anthropic-dns0; sudo ip link del anthropic-dns0
```

## 4. Daily commands (same as the Mac, Linux tools)

| What | Command |
|---|---|
| Status | `bash /usr/local/anthropic-tunnel/bin/status.sh` |
| Off on purpose (grey; Anthropic goes direct, knowingly) | `sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh` |
| On | `sudo /usr/local/anthropic-tunnel/bin/tunnel-up.sh` |
| Restart daemon | `sudo /usr/local/anthropic-tunnel/bin/tunnel-restart.sh` |
| Live log | `journalctl -fu anthropic-tunnel` |
| DNS layer detail | `resolvectl status anthropic-dns0` |
| Fake-IP check | `resolvectl query claude.ai` → `198.18.x.x -- link: anthropic-dns0` |
| Tunnel check | `curl -s --max-time 15 -o /dev/null -w "HTTP %{http_code} remote_ip=%{remote_ip}\n" https://api.anthropic.com/v1/models` → `401`, `remote_ip=198.18.…` |
| Current transport | `curl -s -H "Authorization: Bearer $(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)" http://127.0.0.1:9090/proxies/anthropic` |
| Switch transport | same URL with `-X PUT -d '{"name":"vless-out"}'` (or `wg-out`) |
| Active Anthropic connections and chains | `curl -s -H "Authorization: Bearer $(cat /usr/local/anthropic-tunnel/etc/clash-api.secret)" http://127.0.0.1:9090/connections \| python3 -c "import sys,json; d=json.load(sys.stdin); [print((c['metadata'].get('host') or c['metadata'].get('destinationIP')), '->', c['chains']) for c in d['connections'] if 'anthropic' in c['chains']]"` |
| Uninstall everything | `sudo bash client-linux/scripts/uninstall.sh` |

## 5. Transport: VLESS now, WireGuard after the server peer

Until `spec/history.md` records "Linux WireGuard peer deployed", switch the
selector to `vless-out` (table above) and run the checks with it. Once the
peer is deployed, switch back to `wg-out` and verify `api check: 401` again.
The choice persists in `/usr/local/anthropic-tunnel/var/cache.db`.

## 6. Verification matrix (all must pass; record results in spec/08)

Same meaning as the Mac tests T1–T10 in spec/06, Linux commands. Before
each test say in chat what you are about to do; tests L3 and L5 interrupt
Anthropic traffic for seconds.

| # | Test | Command / expected |
|---|---|---|
| L1 | API through tunnel | curl line above → 401, `remote_ip=198.18.…`; `journalctl -u anthropic-tunnel` shows `wg-out` (or `vless-out`) for `api.anthropic.com` |
| L2 | Browser | open https://claude.ai (Firefox/Chrome, default DNS settings): loads; connections list shows claude.ai hosts on the `anthropic` chain |
| L3 | Kill switch | `sudo systemctl stop anthropic-tunnel; resolvectl flush-caches` → `resolvectl query claude.ai` fails ("Connection refused"), curl → `Could not resolve host`, `curl https://github.com` → 200; `ip link show anthropic-tun0` gone. Then `sudo systemctl start anthropic-tunnel` → L1 passes again |
| L4 | Crash restart | `sudo kill -9 $(systemctl show -p MainPID --value anthropic-tunnel)` → new PID within ~4 s (`systemctl show -p NRestarts`), L1 passes |
| L5 | Down/up by user | `tunnel-down.sh` → both units disabled, `anthropic-dns0` gone, `resolvectl query claude.ai` gives a real IP (grey, intentional); `tunnel-up.sh` → L1 passes |
| L6 | Non-Anthropic direct | `curl -s https://github.com -o /dev/null -w "%{remote_ip}\n"` is a real IP; journal shows `outbound/direct` for it; `resolvectl dns` lists `172.30.250.9:5553` only under `anthropic-dns0`, never under Global |
| L7 | Reboot | `sudo reboot`; after login `status.sh` healthy with no manual action; `systemctl is-enabled anthropic-tunnel anthropic-tunnel-dns` both enabled |
| L8 | NetworkManager (Desktop) | `nmcli device status` shows `anthropic-dns0` and `anthropic-tun0` as `unmanaged`; after toggling Wi-Fi off/on, `resolvectl status anthropic-dns0` still lists the six `~domains` |
| L9 | Per-link upstream DNS | `resolvectl dns` shows the upstream (router/DHCP) on the physical link, not only under Global. If it is only Global, non-Anthropic lookups through sing-box fail (spec/08 explains); report, do not patch sing-box |
| L10 | Own-DNS app | `dig @8.8.8.8 claude.ai` → `198.18.x.x` (port 53 enters the TUN and sing-box answers). `dig @8.8.8.8 github.com` → real IP |
| L11 | Leak audit | after an hour of use: `journalctl -u anthropic-tunnel --no-pager \| grep -iE 'anthropic\|claude' \| grep -c 'outbound/direct'` → 0 |
| L12 | Uninstall (only if the operator asks; cuts the agent's line) | `uninstall.sh` → no units, link, rules, sudoers, files; DNS normal |

## 7. Native Wayland tray (desktop only)

The GTK 3/AppIndicator frontend uses the shared Python status/action backend.
Install Python GI, GTK 3 and Ayatana AppIndicator3 (or AppIndicator3) bindings,
and use a desktop with a StatusNotifier host (Ubuntu AppIndicators on GNOME).
Check dependencies, then install without sudo:

```bash
/usr/bin/python3 menubar/anthropic-tunnel-tray.py --check
bash menubar/install-linux.sh
```

The installer launches the tray and adds desktop/login entries. Launch it
again with `~/.local/bin/anthropic-tunnel-indicator`. Status, controls,
configured transports, statistics, logs, diagnostics and DNS flushing are in
the menu. Multiple launches activate the existing instance. Quit closes only
the indicator; Disconnect stops the tunnel and removes DNS protection.

Revert the indicator installation with `bash menubar/uninstall-linux.sh`;
this leaves the tunnel running. For installed paths and test results see
spec/08. Ubuntu Server has no panel: use `status.sh` instead.

## 8. Known pitfalls (found in the container run, 2026-10-29)

- **Empty or foreign `/etc/resolv.conf`.** glibc then skips resolved and
  sing-box's `local` server falls back to `[::1]:53`; every non-Anthropic
  lookup fails. Real Ubuntu has the stub symlink; if it does not, stop and
  report (do not edit resolv.conf on your own).
- **No per-link upstream DNS in resolved** (only a global `DNS=`): same
  symptom. DHCP via NetworkManager/networkd normally sets it per link.
- **`resolvectl query` answers from cache** for up to 600 s after sing-box
  stops: the stale fake IP has no route, so connections still fail
  (fail-closed), but a "does it resolve" test needs `resolvectl
  flush-caches` first.
- **Two clients on one WireGuard peer** steal each other's session. Never
  reuse the Mac's key; the Linux peer is separate.
- **`systemctl stop anthropic-tunnel` by hand** shows grey `?` in the
  indicator (enabled but not running) and stays fail-closed; `tunnel-down.sh`
  is the only way to grey-with-direct.

## 9. Report back

When done, in one commit (the operator's go for the commit and the push):
`spec/08-client-linux.md` gets the real-machine section with the L1–L12
table filled, `spec/history.md` one dated line, `spec/todo.md` items 6 and
7 moved or updated, `MANUAL.md` (Linux rows and sections) corrected where a command or
behaviour differed, and `spec/decisions.md` for anything you had to decide
differently from spec/08 (say why, and what was rejected). Nothing personal
in any of them; that goes to `private/notes.md`.

# 06 — Operations

## Secrets

Location: `private/secrets/` (the whole `private/` folder is git-ignored;
CLAUDE.md rule 4). Create it before anything else.

| File | Content | How to create |
|---|---|---|
| `server.env` | `SERVER_IP=`, `SSH_USER=root`, `SSH_PORT=22`, `SSH_KEY=` (path to the private key) | copy `server/.env.example`, fill in |
| `wg-server.key` / `wg-server.pub` | server WireGuard key pair | `sing-box generate wg-keypair` |
| `wg-client.key` / `wg-client.pub` | macOS client WireGuard key pair | `sing-box generate wg-keypair` |
| `wg-linux.key` / `wg-linux.pub` | Linux client WireGuard key pair | `sing-box generate wg-keypair` |
| `wg-psk.key` | WireGuard pre-shared key (32 random bytes, base64) | `sing-box generate rand --base64 32` |
| `vless-uuid` | VLESS user id | `sing-box generate uuid` |
| `reality.key` / `reality.pub` | Reality key pair | `sing-box generate reality-keypair` |
| `reality-shortid` | 8 hex digits | `sing-box generate rand --hex 4` |
| `clash-api.secret` | local Clash API password (indicator reads it from the installed copy) | `sing-box generate rand --hex 16` |

One value per file, no trailing newline needed (render scripts strip it),
mode 600. Nothing from this folder is ever pasted into chat, a spec or a
commit. If a value leaks, generate a new one and re-render both sides.

## First setup order

1. Server pre-flight (read-only) → choose ports/subnet → record in decisions.md.
2. Generate keys on the Mac into `private/secrets/`; render server config; copy up;
   `docker compose up -d`; verify with `docker logs`.
3. Mac: install sing-box, render client config, test in foreground first
   (`sing-box run -c ...`), then `sudo bash client/scripts/install.sh`
   (kills the foreground instance, installs, loads the daemon, prints status).
4. Install SwiftBar (the operator clicks), drop plugin, confirm states.
5. Tests below.
6. Update history.md. (No SSH/password hardening: shared server, not ours
   to change. Key auth is already in place.)

## Tests (all must pass before "done")

| # | Test | Expected |
|---|---|---|
| T1 | `curl https://api.anthropic.com` on Mac with tunnel up | reaches server (server log shows the connection), menu bar turns yellow |
| T2 | Open claude.ai in Chrome | loads; sing-box log shows outbound `wg-out` (or `vless-out`) |
| T3 | Stop the server container | within 10 s menu bar RED; claude.ai refuses to load; `curl` fails (timeout, WireGuard drops silently), NOT a direct success |
| T4 | Start container again | GREEN within 10 s, traffic resumes |
| T5 | `kill -9` sing-box on Mac | launchd restarts it; during the gap Anthropic hosts are refused by the leak guard |
| T6 | Non-Anthropic site (e.g. github.com) | goes direct, server log shows nothing |
| T7 | tunnel-down.sh | GREY; claude.ai loads directly (known, intentional) |
| T8 | uninstall.sh | Mac exactly as before: no utun, no daemon, no resolver files, no sudoers entry, DNS normal |

## Test results 2026-10-28 (foreground run, before launchd install)

| # | Result |
|---|---|
| T1 | PASS. api.anthropic.com → fake IP 198.18.0.3 → wg-out; server log shows the connection |
| T2 | PASS. claude.ai login page loads in the built-in browser through the tunnel |
| T3 | PASS. Server container stopped: api.anthropic.com and claude.ai time out from curl, browser cannot load claude.ai, github.com still 200 |
| T4 | PASS. Container started: traffic resumed (after the DNS-rule fix) |
| T5 | PASS. `sudo pkill -9 -x sing-box`: launchd restarted it in under 1 s (status 1 s after the kill already showed the new process, third `sing-box started` in the log, TUN and fake IPs back, api 401 via tunnel). Gap fail-closed by the resolver files. |
| T6 | PASS. github.com, google.com, cloudflare.com direct, exit IP = the Mac's own public IP |
| T7 | PASS (after install). `sudo -n tunnel-down.sh`: daemon unloaded, resolver files gone, claude.ai → real IP, api direct 401 (grey, intentional). `sudo -n tunnel-up.sh`: daemon back, 6/6 resolver files, fake IP, api 401 via tunnel. No password asked. |
| T8 | dry review only (real run would cut the agent's line). uninstall.sh targets all exist; script body moved into a function so it survives deleting its own installed copy. Real run deferred to the operator. |

| T9 | PASS (2026-10-28, phase 2). Selector switched to vless-out via API: new connections show chain vless-out→anthropic, api 401 in ~1.0 s, delay probe 538 ms; switched back to wg-out via the plugin's Transport action: api 401 in 0.65 s. Menu shows both transports with the active one checked. |

| T10 | PASS (2026-10-28 15:22). Mac rebooted: daemon pid 589 started by launchd 28 s after boot (runs = 1, no manual action), 6/6 resolver files, TUN up, claude.ai → fake IP, api 401 via tunnel, SwiftBar running with the plugin in the active state, selector on wg-out. |

Also verified: a-cdn / s-cdn / assets-proxy (CDN hosts on Google IPs) go
through the tunnel; HTTPS-type DNS queries for Anthropic names return no
address hints.

## Linux client tests

The container run on the Mac (2026-10-29) and the remaining real-machine
tests are in `spec/08-client-linux.md`; `bash tests/linux-container/run.sh`
repeats the container run. Manual revert on Ubuntu:

```
sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh
```
If the scripts are broken:
```
sudo systemctl disable --now anthropic-tunnel anthropic-tunnel-dns
sudo resolvectl revert anthropic-dns0; sudo ip link del anthropic-dns0
```

## Leak guard tests (T11 to T13)

| # | Test | Expected |
|---|---|---|
| T11 | `sudo bash client/scripts/guard-install.sh` | self-test: Anthropic 401 through the tunnel; fake-IP probe on the physical interface refused in under 1 s; indicator shows `Leak guard: on` |
| T12 | Another VPN connected (or `sudo route add -net 160.79.104.0/21 <LAN gateway>` as a stand-in, removed right after) | every Anthropic connection is refused at once; `sudo bash /usr/local/anthropic-tunnel/bin/guard.sh status` shows the block counters rising; other sites work |
| T13 | System proxy switched on in System Settings | indicator red `PROXY` with a notification; off again → normal |

Results on the operator's Mac, 2026-10-29:

| # | Result |
|---|---|
| T11 | PASS. Self-test: Anthropic 401 through the tunnel; fake-IP probe on en0 refused after 0.002 s. Anchor loaded with pass on utun7; static table 4 ranges, dynamic table 3 addresses. Indicator: `Leak guard: on, 3 extra addresses`. |
| T12 (stand-in) | PASS. Requests forced out of en0 around the tunnel (`curl --interface en0` with the real address): api.anthropic.com and claude.ai (160.79.104.10), a-cdn (34.36.57.103), downloads (35.190.46.17) all refused in under 0.001 s; github.com on the same path 200. A real second VPN is still to be tried. |
| T5 with guard | PASS. `tunnel-restart.sh`: Anthropic back within 1 s, guard pass interface follows the tunnel utun, en0 bypass still refused. |
| T13 | open (needs a system proxy switched on by hand) |

Linux equivalents run in the container test and in the Linux runbook.

## Operational rule: other VPN apps

The leak guard refuses every packet to Anthropic that does not leave
through this tunnel, so another VPN running at the same time cannot carry
Anthropic traffic; Anthropic simply stops working until that VPN releases
the routes. Proxies are different: a system proxy or a NetworkExtension
transparent proxy takes connections before pf sees them. The indicator turns
red with `PROXY` when one is on. Switch it off, or disconnect the tunnel
first (grey) if you really need it.

## Manual revert (memorise)

```
sudo /usr/local/anthropic-tunnel/bin/tunnel-down.sh
```
(unloads the daemon, lifts the leak guard and removes the resolver files;
Anthropic goes direct). Only the leak guard:
`sudo bash /usr/local/anthropic-tunnel/bin/guard-off.sh`.
Full removal: `sudo bash client/scripts/uninstall.sh`. If the scripts
themselves are broken:
```
sudo launchctl bootout system/local.anthropic-tunnel
sudo rm -f /etc/resolver/anthropic.com /etc/resolver/claude.ai /etc/resolver/claude.com /etc/resolver/claude.app /etc/resolver/claudeusercontent.com /etc/resolver/claudemcpcontent.com
```

## Server removal

See 03 — one `docker compose down -v` and folder delete.

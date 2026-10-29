# History

- 2026-10-28 · Project created. Requirements gathered in chat: fail-closed
  tunnel for all Anthropic traffic, Docker on server, sing-box TUN on Mac,
  SwiftBar indicator with green/yellow/red(/grey), WireGuard then VLESS.
  Repo structure, CLAUDE.md and specs 00–06 written. Sonnet research agent
  dispatched for the complete Anthropic domain list (02 pending).
  Root password was shared in chat → flagged for rotation. Nothing deployed.
- 2026-10-28 · Domain research completed (Sonnet agent, 32 tool calls, official
  docs + live curl checks). spec/02 filled: 6 apexes, per-product hosts,
  third-party hosts (decision pending), 8 unverified items with how to close them.
- 2026-10-28 · The operator decided: third-party hosts (GitHub, npm, Cloudflare,
  Google, Datadog) stay off the tunnel; only Anthropic apexes. Rule added to
  CLAUDE.md. Rule added: no code without explicit permission. Stack proposal
  written in spec/07-stack.md, awaiting approval.
- 2026-10-28 · Server pre-flight done (read-only, via password SSH through an
  expect wrapper kept outside the repo; creds in private/secrets/server.env). Results in
  spec/03. Findings needing the operator: a foreign SSH key on root (a
  colleague's), no host firewall, password root login enabled.
- 2026-10-28 · The operator's public key appended to root
  authorized_keys; key login verified. Password removed from private/secrets/server.env
  and the expect wrapper deleted. Rules updated: shared server, no host config
  changes, no hardening.
- 2026-10-28 · Rule 11 (US location) added; server verified US. sing-box 1.14.4
  installed on the Mac via brew. WireGuard keys, PSK and Clash API secret
  generated into private/secrets/. server/docker-compose.yml, config template and
  render.sh written; rendered config passes `sing-box check`. Not deployed.
- 2026-10-28 · Server stack deployed to /opt/anthropic-tunnel. Found and fixed:
  foreign notrack rule breaks bridge NAT → host network; PMTU 1420 → MTU 1280.
  End-to-end WireGuard test from the Mac passed (exit IP = server, Anthropic
  hosts reachable through the tunnel). Host services untouched. Container ~9 MiB.
- 2026-10-28 · Mac client config template + render script written and
  validated with sing-box check (TUN, fake-ip, hijacked DNS, DNS-in-tunnel,
  no direct path for Anthropic). Not yet run: TUN needs root, the operator runs it.
- 2026-10-28 · First TUN run on the Mac (foreground, the operator's sudo). Passed:
  Anthropic connections → wg-out incl. CDN hosts via SNI sniff; general
  traffic direct; claude.ai loads in the built-in browser; T3 kill switch
  (server container stopped → Anthropic times out, browser fails, github
  fine); T4 recovery. Found: macOS system DNS not hijacked → added
  /etc/resolver files (fake IPs confirmed). Found: DNS reject rule also hit
  sing-box's internal lookup → rules fixed, restart pending.
- 2026-10-28 · sing-box restarted with fixed DNS rules (old process had to be
  killed; a second instance cannot start while the first holds cache.db).
  Fake-IP path verified end to end for six hosts. The operator's warning recorded as
  CLAUDE.md rule 12: never cut the agent's own line to Anthropic or SSH.
- 2026-10-28 · launchd plist, install/uninstall/up/down/restart/status
  scripts and sudoers line written and syntax/visudo-checked. Install layout
  moved to /usr/local/anthropic-tunnel (no spaces). Not installed yet.
- 2026-10-28 · Client installed via install.sh (daemon local.anthropic-tunnel,
  sing-box 1.14.4 at /usr/local/anthropic-tunnel). T7 passed through sudoers.
  T8 reviewed dry. uninstall.sh hardened (function body). T5 awaiting the operator's
  `sudo pkill -9 -x sing-box` run.
- 2026-10-28 · T5 passed (kill -9 → launchd restart < 1 s). Phase 1 complete:
  persistent fail-closed tunnel for all Anthropic traffic is live on the Mac.
- 2026-10-28 · Menu bar indicator live: SwiftBar 2.1.1 (old 2.0.1 crashed,
  trashed), plugin menubar/anthropic-tunnel.5s.py, states green/yellow/grey
  verified, red debounced after a real link hiccup. The operator's own ping
  plugin piles up (5 pings/s), left untouched, reported.
- 2026-10-28 · Menu bar colours changed to light/dark pairs (yellow invisible on
  light bar). Old SwiftBar 2.0.1 deleted from Trash with its crash reports;
  2.1.1 (brew cask, auto-updating) stays.
- 2026-10-28 · Menu bar title shortened (narrow, e.g. "↑4K ↓2K", "640ms");
  ACTIVE colour changed from yellow to orange after the operator could not read it.
  Screen captures confirmed the item is visible in the bar.
- 2026-10-28 · ACTIVE colour changed to blue at the operator's request.
- 2026-10-28 · Menu bar colours set to dark tones (dark green, dark blue, dark red, dark grey) at the operator's request.
- 2026-10-28 · Phase 2: VLESS+Reality inbound live on the server (TCP 8444),
  verified from the Mac with a temporary SOCKS client (exit IP = server,
  Anthropic hosts answer). Client config now has both transports in the
  selector; daemon config update awaiting the operator's sudo.
- 2026-10-28 · Daemon now runs both transports; T9 (switch wg↔vless) passed. Phase 2 complete.
- 2026-10-28 · Rule 0 verified live across clients: Chrome sockets (lsof) go to fake IPs through the TUN; claude.ai, assets, s-cdn, assets-proxy, bridge, api, platform all on chain anthropic; zero Anthropic destinations ever on direct since install; hard-coded-IP and interface-bound bypass attempts cannot reach Anthropic directly.
- 2026-10-28 · Docs refreshed to live state (01 rewritten, 06/07/README fixed), spec/todo.md created, operator manual written; rules 6 and 7 extended to cover the manual and todo list.
- 2026-10-28 · T10 passed: after a Mac reboot the daemon, resolver files, TUN, menu bar and tunnel all came back without manual action. All acceptance tests closed except the real T8 run.
- 2026-10-28 · Menu bar overflow found: the operator's ping plugin compacted and set to 10 s (backup kept), tunnel item narrowed to icon-only when idle. Not everything fit yet; remaining fix was the operator's (details in private/notes.md).
- 2026-10-28 · The operator freed menu bar space; all items visible. Overflow item closed.
- 2026-10-28 · Menu bar colours set to Apple system colours with bold title after dark tones were unreadable; a regex edit briefly broke the plugin header (restored from git); __pycache__ now git-ignored.
- 2026-10-28 · Idle title was empty and SwiftBar hid the item; idle now shows a green ✓.
- 2026-10-28 · SF Symbol icon never took sfcolor; replaced by embedded coloured PNG icons generated by menubar/make_icons.py. Icon now green/blue/red/grey like the text.
- 2026-10-29 · Menu bar: ACTIVE now needs at least 4096 bytes per tick (keepalives and probes no longer turn the item blue); while still inside the 10 s window with no bytes this tick the title shows `↓0`. Manual table updated.
- 2026-10-29 · Ubuntu Linux client written (client-linux/: sing-box template with a resolved-facing DNS listener, render.sh, two systemd units, dns-layer/up/down/restart/status/install/uninstall scripts), Linux WireGuard key generated, server template given a second peer (not deployed), indicator plugin made platform-aware (Argos on GNOME; macOS output verified unchanged and reinstalled), spec/08 written. Research by a Sonnet agent (sing-box Linux TUN/dns_mode, .deb vs tarball, resolved routing domains, Argos, Ubuntu defaults). Tested in a privileged systemd Ubuntu 24.04 container on the Mac (tests/linux-container/): install, DNS layer, TUN, VLESS tunnel, kill switch, kill -9 restart, resolved restart, down/up, container restart, uninstall, plugin: all passed. Found on the way: sing-box `local` on Linux needs per-link upstream DNS in resolved (otherwise it falls back to [::1]:53); a loopback DNS listener is treated by resolved as usable for every name, so the listener moved to the dummy link address. Mac leak audit after the work: zero Anthropic destinations on direct in the whole log, all live Anthropic connections on wg-out, macOS client files untouched.
- 2026-10-29 · `client-linux/README.md` written: the runbook for the agent on the Ubuntu machine (rules that apply there, read-only pre-flight, how the rendered config gets there, what install.sh changes, daily commands, VLESS-first until the server peer exists, tests L1–L12, Argos, known pitfalls, how to report back). Linked from CLAUDE.md, spec/08 and the manual.
- 2026-10-29 · MIT license added.
- 2026-10-29 · Public documentation: README.md rewritten as the full guide (purpose, how it works, domains, platform status, requirements, setup from an empty clone with a tested secrets block, daily use, revert and uninstall, limitations, working with an agent, documentation map); MANUAL.md written for macOS and Linux; server/.env.example matches the keys in use; plugin and icon generator use env python3 and the macOS installer pins the local interpreter.
- 2026-10-29 · Operator data kept in the git-ignored `private/` folder (private/secrets/, notes.md, backups/); render scripts read `private/secrets/`; CLAUDE.md rule 4 and the README describe the convention. Fresh-clone test of the README secrets block passed.


- 2026-10-29 · Prepared a real Linux workstation for VLESS: retrieved only the
  project listener's client credentials over read-only SSH, derived the Reality
  public key on the server without copying its private key, and generated a
  separate local Clash API secret. Credentials and generated config remain
  git-ignored. Added `render.sh --vless-only`, moved Linux TUN/DNS IPv4 addresses
  away from a local Docker subnet, and updated the Linux indicator check.
  Verified the pinned amd64 archive SHA256, config validation, and a temporary
  SOCKS-to-VLESS API probe (HTTP 401); the probe was then removed. No server or
  host network changes. Installation and real TUN/DNS tests await interactive
  sudo authentication. Environment details are in `private/notes.md`.

- 2026-10-29 · Real Linux installation completed by the user. Diagnosed the
  daemon restart loop from `set routes: add route 0: file exists`: another VPN
  TUN was active again and owned table 2022. The user disabled its TUN mode;
  restarted only the project daemon through its installed sudoers action.
  Verified active/running service, zero restarts after that restart, DNS 6/6,
  TUN up, fake-IP resolution and Anthropic API HTTP 401 via vless-out. DNS
  protection stayed active throughout. Full shutdown/recovery and reboot
  tests remain open; no server changes.

- 2026-10-29 · Installed Argos and its plugin, confirmed the plugin reported a
  healthy VLESS connection; enabling Argos required a Wayland logout. At the
  user's request, replaced the Linux UI with a GTK/AppIndicator frontend,
  installed/launched it, added application/login entries and disabled only
  this project's old Argos plugin. Verified live GNOME StatusNotifierItem
  registration, connected menu, native Wayland GTK backend, single-instance
  activation, quit/relaunch and uninstall/reinstall with unchanged tunnel PID. No sudo or tunnel/server changes. Login autostart
  remains to be verified at the next login.

- 2026-10-29 · Prepared all six VLESS client profiles from read-only server
  inspection. Retained the project default; imported Reality, WebSocket, two
  TLS profiles with trusted public-key pins, and XHTTP via a pinned local Xray
  helper. Added persistent secret-profile merging, helper installation and a
  config-only apply script with backup/startup rollback and off-state
  preservation; uninstall removes the helper too. Config/API/DNS probes passed
  (WebSocket UDP passed on focused retest); wrong-pin verification rejected the
  peer. No server writes. Root installation of the imported profiles remains
  pending interactive sudo. The installed project tunnel was observed disabled
  while another TUN was active; preserved that state.

- 2026-10-29 · Confirmed imported profiles and XHTTP helper installed: all six
  choices visible in the live API, original VLESS selected, main/DNS/helper
  services active. Diagnosed Google failure: IPv4 HTTP 200, ordinary/IPv6 TLS
  reset, no physical IPv6 default route and direct outbound IPv6 errors.
  Prepared persistent per-machine IPv4-only TUN rendering. Validated config
  and confirmed no profile/DNS/routing rule changes. Applying this adjustment
  and checking ordinary browser access await interactive sudo.

- 2026-10-29 · User applied the IPv4-only TUN option. Verified ordinary Google
  HTTP 200, matching direct public-IP observers, and server egress reported by
  Anthropic API/Claude trace endpoints. Current-invocation audit: 53 tunneled
  Anthropic entries, zero direct matches across 421 log lines. Verified boot
  enablement and two-second restart policy; real crash/reboot tests remain
  open. Prepared Linux client/profile/Wayland tray changes for pull-request
  review; credentials, rendered configs, binaries and host-specific records
  remain excluded from Git.

- 2026-10-29 · Ported the Linux changes onto the replacement repository's
  fresh main history. Preserved its public docs and macOS identifiers, adopted
  `private/secrets/`, and integrated operating instructions into `MANUAL.md`
  and the Linux runbook. Installer metadata now parses JSON for both VLESS-only
  and WireGuard configurations. No live services were changed during the port.

- 2026-10-29 · macOS leak guard added: pf anchor `com.apple/250.anthropic-tunnel` with static Anthropic and fake-IP ranges plus dynamic load-balancer addresses, pass only on our utun; launchd jobs for a 5 s apply loop and a 5 min refresh; `guard-install.sh` with self-test and automatic rollback; `guard-off.sh` revert; control scripts lift and restore it with grey/connect. `shared/guard-ips.sh` resolves addresses through sing-box's local API (3 Google Cloud addresses on 2026-10-29; CDN-shared hosts skipped). Indicator (macOS only): guard line, red `GUARD` when missing or stale, red `PROXY` for system or NetworkExtension proxies, other connected VPNs listed. Generated pf rules pass `pfctl -n`; install awaits the operator's sudo. Server checked read-only: stack healthy, only the macOS WireGuard peer configured, 46 WireGuard "message too long" send errors in 24 h (path MTU toward the client on some networks).
- 2026-10-29 · Linux leak guard (nftables table `inet anthropic_guard`, output and forward chains, boot-time unit before the network and the tunnel, 60 s refresh timer, flock-serialized) included; container test passed (route bypass like another VPN refused in under 1 ms, dead daemon with real-IP access refused, IPv6 rule hit, grey/connect, boot order, uninstall clean). macOS stays the tested and maintained client.
- 2026-10-29 · macOS leak guard installed on the operator's Mac (`guard-install.sh`): self-test passed, en0 bypass to every guarded Anthropic address refused in under a millisecond while other sites work, guard follows a tunnel restart, new indicator installed and shows the guard. pf was already enabled by another component, so no pf reference was taken. Installer now prints the full guard status.

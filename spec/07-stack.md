# 07 — Stack (approved by the operator 2026-10-28)

Principle: as few languages and moving parts as possible; nothing compiled;
everything readable in a text editor; pinned versions recorded here once
chosen (never "latest").

## Server

| Piece | Choice | Why |
|---|---|---|
| Runtime | Docker + Docker Compose (already on the server) | isolation, one-command removal |
| Tunnel daemon | sing-box, official image `ghcr.io/sagernet/sing-box`, pinned tag | one binary does WireGuard inbound now and VLESS+Reality inbound later, same config format on both sides |
| Config | JSON (sing-box native) | no templating engine; rendered from a template by a shell script that substitutes keys from `private/secrets/` |
| Firewall rule | the tool already in use on the server (ufw or nftables, seen in pre-flight) | do not introduce a second firewall |
| Language for scripts | POSIX shell (`sh`), `set -eu` | runs anywhere, no dependencies |

## Mac client

| Piece | Choice | Why |
|---|---|---|
| Tunnel daemon | sing-box, Homebrew formula `sing-box`, pinned version | TUN, fake-ip DNS, rule routing, Clash API, WireGuard and VLESS outbounds in one binary |
| Service manager | launchd (system daemon plist) | native, auto-start before login, KeepAlive restart |
| Second layer | `/etc/resolver` per-domain files (macOS built-in) | fail-closed DNS for the six apexes even when the daemon is down |
| Optional third layer | pf anchor (macOS built-in) | only for the other-VPN-running case; not installed (todo.md) |
| Scripts | bash (macOS ships 3.2; scripts stay 3.2-compatible) | install, uninstall, up, down, render-config, refresh-pf-table |
| Secrets rendering | `envsubst` is not on macOS by default; use `sed` substitution of `__KEY__` placeholders | no new dependency |

## Linux client (Ubuntu 24.04; added 2026-10-29)

| Piece | Choice | Why |
|---|---|---|
| Tunnel daemon | sing-box, official release tarball `sing-box-1.14.4-linux-{amd64,arm64}.tar.gz`, sha256 pinned in `client-linux/scripts/install.sh` | same version as the Mac and the server; the `.deb` would add its own unit, user, polkit and D-Bus policies |
| Service manager | systemd (`anthropic-tunnel.service`, `anthropic-tunnel-dns.service`) | native, boot-time, `Restart=always` |
| Second layer | systemd-resolved routing domains on a dummy link (`anthropic-dns0`) | fail-closed DNS for the six apexes even when the daemon is down; Ubuntu Desktop and Server both run resolved |
| Scripts | bash | same scripts as macOS, systemd/iproute2/resolvectl instead of launchctl/ifconfig/resolver files |
| Indicator | Argos (GNOME Shell extension, BitBar format) running the same Python plugin | no new language; Argos master supports GNOME 45–51 |
| Test rig | Docker Desktop on the Mac, `tests/linux-container/` (Ubuntu 24.04 + systemd, privileged) | the only Linux available here; limits in spec/08 |

## Menu bar

| Piece | Choice | Why |
|---|---|---|
| Host app | SwiftBar (Homebrew cask, pinned) | mature, supports dynamic enable/disable of menu items, colours, icons, refresh interval, runs scripts on click |
| Plugin language | Python 3 (present on macOS via Xcode CLT or Homebrew; verified in pre-flight, not assumed) with stdlib only (`urllib`, `json`, `subprocess`) | the plugin needs JSON parsing of the Clash API, byte-rate deltas and state logic; doing that in bash is fragile. No pip packages. |
| Fallback if python3 is absent | bash + `curl` + `jq` (Homebrew) | decided only if pre-flight shows no python3 |
| Icon | one SVG (three concentric circles) → PNG template at 2x, base64-embedded in the plugin, tinted per state by SwiftBar's `color=` | no image files to ship separately |
| Root actions (connect/disconnect/restart) | `sudo` with a `sudoers.d` entry limited to the three scripts by absolute path, `NOPASSWD` | menu click must work without a password prompt; scope limited |
| Notifications | `osascript display notification` | built-in |

## Tests

| Piece | Choice |
|---|---|
| Test runner | bash scripts in `tests/`, one file per test T1–T8 from spec/06, exit code 0/1, run by `tests/run-all.sh` |
| Server-side checks | `docker compose logs`, `docker exec sing-box sing-box check` |

## Not used, on purpose

- Node, Go, Rust, Swift compilation: nothing to build.
- Clash / mihomo / Xray: sing-box alone covers both ends and both protocols.
- A second firewall on the server, Network Extension apps, GUI VPN clients.
- Any pip/npm dependency.

## Versions (filled in after pre-flight, then pinned)

| Component | Version | Date pinned |
|---|---|---|
| sing-box (server image) | ghcr.io/sagernet/sing-box:v1.14.4 | 2026-10-28 |
| sing-box (Mac, brew) | 1.14.4 | 2026-10-28 |
| SwiftBar | 2.1.1 (brew cask, auto-updates); old manual 2.0.1 removed | 2026-10-28 |
| python3 on Mac | 3.x, Homebrew or Xcode CLT; stdlib only; `menubar/install.sh` pins the interpreter it finds | 2026-10-28 |
| Docker / Compose on server | 29.4.0 / v5.1.2 (already present) | 2026-10-28 |
| macOS | any version that runs sing-box 1.14.4 and SwiftBar 2.1.1 (tested build in `private/notes.md`) | 2026-10-28 |
| sing-box (Linux, tarball) | 1.14.4, sha256 in install.sh | 2026-10-29 |
| Ubuntu target | 24.04 LTS (systemd 255, resolved, python3 3.12) | 2026-10-29 |
| Argos | git master (GNOME 45–51), not the stale extensions.gnome.org build | 2026-10-29 |

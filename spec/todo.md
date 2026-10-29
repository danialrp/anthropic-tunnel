# Open tasks

Kept current with every change. Done items move to `history.md`.

| # | Task | Priority | Owner | Notes |
|---|---|---|---|---|
| 2 | pf third layer: block Anthropic IP ranges and 198.18.0.0/15 on any interface except utun, for the case where another VPN app takes the default route | optional | agent (with the operator's go) | design in 04; needs a tested one-line revert first |
| 3 | Log review after one week: find any Anthropic-related host that went `direct` and add it to spec/02 | optional | agent | `grep outbound/direct /var/log/anthropic-tunnel/sing-box.log` filtered by anthropic/claude |
| 4 | T8 real run of `uninstall.sh` (cuts the agent's line; the operator runs it when they want) | low | the operator | dry-reviewed 2026-10-28 |
| 5 | Deploy the Linux WireGuard peer: `sh server/render.sh`, copy `server/sing-box/config.json` to the server, `docker compose restart` (rule 3: the operator's go first) | high | agent (with the operator's go) | template and render.sh already updated 2026-10-29; Mac peer unchanged |
| 6 | Complete real Ubuntu acceptance tests: daemon failure/recovery, fail-closed DNS, NetworkManager persistence, reboot, and WireGuard after its peer is deployed | high | the operator + agent | container tests passed; real installation, TUN/DNS 6/6, fake-IP lookup and VLESS API HTTP 401 passed on 2026-10-29 after the competing VPN TUN was disabled; remaining checks in spec/08 |
| 7 | Verify GTK/AppIndicator startup at the next desktop login and exercise menu controls | medium | user + agent | installed and live on Wayland; GNOME registration/menu, single-instance and quit/relaunch checks passed; autostart configured |
| 8 | Evaluate sing-box `auto_redirect` on Linux after the real-machine run (sing-box recommends it; adds nftables rules, redirects port 53 itself) | optional | agent | spec/08 open points |
| 9 | Test imported profile switching and XHTTP service reboot behaviour on the real host | high | user + agent | all six profiles visible in live API; helper installed and active; isolated API/DNS probes passed |

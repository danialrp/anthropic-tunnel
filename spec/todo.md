# Open tasks

Kept current with every change. Done items move to `history.md`.

| # | Task | Priority | Owner | Notes |
|---|---|---|---|---|
| 2 | pf third layer: block Anthropic IP ranges and 198.18.0.0/15 on any interface except utun, for the case where another VPN app takes the default route | optional | agent (with the operator's go) | design in 04; needs a tested one-line revert first |
| 3 | Log review after one week: find any Anthropic-related host that went `direct` and add it to spec/02 | optional | agent | `grep outbound/direct /var/log/anthropic-tunnel/sing-box.log` filtered by anthropic/claude |
| 4 | T8 real run of `uninstall.sh` (cuts the agent's line; the operator runs it when they want) | low | The operator | dry-reviewed 2026-10-28 |
| 5 | Deploy the Linux WireGuard peer: `sh server/render.sh`, copy `server/sing-box/config.json` to the server, `docker compose restart` (rule 3: the operator's go first) | high | agent (with the operator's go) | template and render.sh already updated 2026-10-29; Mac peer unchanged |
| 6 | First run on a real Ubuntu machine: `bash client-linux/render.sh` on the Mac, copy config.json, `sudo bash client-linux/scripts/install.sh`, then the spec/08 checks plus: NetworkManager leaves anthropic-dns0/anthropic-tun0 alone, per-link upstream DNS present (`resolvectl dns`), reboot, WireGuard transport | high | The operator + agent | container run passed 2026-10-29; real-machine items listed in spec/08 |
| 7 | Argos in GNOME Shell: install from git master, `bash menubar/install-linux.sh`, check icon/colours/menu/actions in the top bar | medium | The operator | plugin output verified in the container only |
| 8 | Evaluate sing-box `auto_redirect` on Linux after the real-machine run (sing-box recommends it; adds nftables rules, redirects port 53 itself) | optional | agent | spec/08 open points |

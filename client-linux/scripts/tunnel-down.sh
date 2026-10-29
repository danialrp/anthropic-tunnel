#!/bin/bash
# Disable the tunnel on purpose (GREY state): stop and disable daemon, DNS
# layer and leak guard. Anthropic traffic then goes DIRECT, until tunnel-up.sh.
set -eu
. "$(dirname "$0")/common.sh"
need_root
systemctl disable --now --quiet "$GUARD_TIMER" "$UNIT" "$DNS_UNIT" "$GUARD_UNIT" 2>/dev/null || true
resolvectl flush-caches 2>/dev/null || true
echo "tunnel DOWN (by user): Anthropic traffic now goes direct"

#!/bin/bash
# Disable the tunnel on purpose (GREY state): unload the daemon and restore
# normal DNS for Anthropic domains. Anthropic traffic then goes DIRECT.
set -eu
. "$(dirname "$0")/common.sh"
need_root
if daemon_loaded; then
  launchctl bootout "system/$LABEL"
  echo "daemon unloaded"
else
  echo "daemon was not loaded"
fi
resolver_remove
dscacheutil -flushcache 2>/dev/null || true
echo "tunnel DOWN (by user): Anthropic traffic now goes direct"

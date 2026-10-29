#!/bin/bash
# Copy the plugin into SwiftBar's plugin folder (no sudo) and (re)launch SwiftBar.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
[ -n "$DIR" ] || { echo "SwiftBar has no PluginDirectory yet: launch SwiftBar once and choose a folder" >&2; exit 1; }
# SwiftBar runs plugins with a minimal PATH, so pin the interpreter found now
PY=$(command -v python3 || true)
[ -n "$PY" ] || { echo "python3 not found (brew install python, or xcode-select --install)" >&2; exit 1; }
{ echo "#!$PY"; tail -n +2 "$HERE/anthropic-tunnel.5s.py"; } > "$DIR/anthropic-tunnel.5s.py"
chmod 755 "$DIR/anthropic-tunnel.5s.py"
echo "installed $DIR/anthropic-tunnel.5s.py"
open -a SwiftBar
sleep 2
pgrep -x SwiftBar >/dev/null && echo "SwiftBar running" || echo "SwiftBar not running"

#!/bin/bash
# Install the indicator on Ubuntu GNOME as an Argos plugin (no sudo).
#   bash menubar/install-linux.sh
# Argos (https://github.com/p-e-w/argos) must be installed from its git master
# into ~/.local/share/gnome-shell/extensions and enabled; the extensions.gnome.org
# listing is stale. Plugins live in ~/.config/argos; the file name sets the
# refresh interval (anthropic-tunnel.5s.py = every 5 s).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DIR="$HOME/.config/argos"
mkdir -p "$DIR"
# same plugin file as macOS; only the interpreter line differs
{ echo '#!/usr/bin/python3'; tail -n +2 "$HERE/anthropic-tunnel.5s.py"; } > "$DIR/anthropic-tunnel.5s.py"
chmod 755 "$DIR/anthropic-tunnel.5s.py"
echo "installed $DIR/anthropic-tunnel.5s.py"
if command -v gnome-extensions >/dev/null && gnome-extensions list 2>/dev/null | grep -q '^argos@'; then
  gnome-extensions info 'argos@pew.worldwidemann.com' 2>/dev/null | grep -E 'State|Version' || true
else
  echo "Argos extension not found. Install it:"
  echo "  git clone https://github.com/p-e-w/argos /tmp/argos && mkdir -p ~/.local/share/gnome-shell/extensions && cp -r /tmp/argos/argos@pew.worldwidemann.com ~/.local/share/gnome-shell/extensions/"
  echo "  then log out and back in (Wayland) and: gnome-extensions enable argos@pew.worldwidemann.com"
fi
command -v notify-send >/dev/null || echo "note: notify-send missing (apt install libnotify-bin) - notifications will be silent"
echo "test run:"; "$DIR/anthropic-tunnel.5s.py" | head -3

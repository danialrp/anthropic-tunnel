#!/bin/bash
# Remove only the user tray app and its login entry. Keep the tunnel running.
set -eu
/usr/bin/python3 - <<'PY'
import os, pathlib, subprocess

home = pathlib.Path.home()
data = pathlib.Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
app = data / "anthropic-tunnel/anthropic-tunnel-tray.py"
if app.exists():
    subprocess.run(["/usr/bin/python3", str(app), "--quit"], check=True)
for path in (home / ".local/bin/anthropic-tunnel-indicator",
             data / "applications/anthropic-tunnel.desktop",
             config / "autostart/anthropic-tunnel.desktop",
             app, app.with_name("anthropic-tunnel.5s.py")):
    path.unlink(missing_ok=True)
print("Removed the indicator and login entry. The tunnel service is unchanged.")
PY

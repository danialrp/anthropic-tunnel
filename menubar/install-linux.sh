#!/bin/bash
# Install and launch the Linux AppIndicator tray frontend, without sudo.
# Ubuntu GNOME uses its AppIndicators extension; no Argos or logout needed.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
/usr/bin/python3 "$HERE/anthropic-tunnel-tray.py" --check
/usr/bin/python3 - "$HERE" <<'PY'
import os, pathlib, shlex, shutil, subprocess, sys, time

source = pathlib.Path(sys.argv[1])
home = pathlib.Path.home()
data = pathlib.Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
state = pathlib.Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "anthropic-tunnel"
dest = data / "anthropic-tunnel"
launcher = home / ".local/bin/anthropic-tunnel-indicator"
subprocess.run(["/usr/bin/python3", str(source / "anthropic-tunnel-tray.py"), "--quit"], check=True)
# The quit action crosses D-Bus; allow the previous process to exit before relaunch.
time.sleep(0.5)
for directory in (dest, launcher.parent, data / "applications", config / "autostart", state):
    directory.mkdir(parents=True, exist_ok=True)
for name in ("anthropic-tunnel-tray.py", "anthropic-tunnel.5s.py"):
    shutil.copy2(source / name, dest / name)
launcher.write_text("#!/bin/sh\nexec /usr/bin/python3 " + shlex.quote(str(dest / "anthropic-tunnel-tray.py")) + ' "$@"\n')
launcher.chmod(0o755)
# Disable only our old Argos plugin; keep other Argos scripts untouched.
legacy = home / ".config/argos/anthropic-tunnel.5s.py"
if legacy.exists():
    legacy.rename(legacy.with_name(".anthropic-tunnel.5s.py.disabled"))
quoted = str(launcher).replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$").replace("%", "%%")
desktop = ('[Desktop Entry]\nType=Application\nName=Anthropic Tunnel\n'
           'Comment=Tunnel status and controls\nExec="' + quoted + '"\n'
           'Icon=network-vpn\nTerminal=false\nCategories=Network;\n'
           'X-GNOME-Autostart-enabled=true\n')
for folder in (data / "applications", config / "autostart"):
    (folder / "anthropic-tunnel.desktop").write_text(desktop)
with (state / "indicator.log").open("a") as log:
    subprocess.Popen([str(launcher)], stdout=log, stderr=log, start_new_session=True,
                     stdin=subprocess.DEVNULL, close_fds=True)
print("Installed and launched Anthropic Tunnel indicator. It starts at login.")
print("Launcher:", launcher)
print("Log:", state / "indicator.log")
print("Quit indicator only:", launcher, "--quit")
PY

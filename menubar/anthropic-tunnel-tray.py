#!/usr/bin/python3
"""GTK/AppIndicator frontend for the shared tunnel status code on Linux."""
import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator
except (ValueError, ImportError):
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3 as AppIndicator
from gi.repository import Gio, GLib, Gtk

APP_ID = "io.github.antrpctunnel.Indicator"
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tunnel_status", HERE / "anthropic-tunnel.5s.py")
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
core.STATE_DIR = str(Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "anthropic-tunnel")
core.STATE_FILE = str(Path(core.STATE_DIR) / "indicator-state.json")
core.SECRET_FILE = "/usr/local/anthropic-tunnel/etc/clash-api.secret"


class TunnelIndicator(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.indicator = None
        self.busy = False
        self.closing = False
        self.timer = None
        self.pending_action = None
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.stop())
        self.add_action(quit_action)

    def do_activate(self):
        if self.indicator is not None:
            return
        self.hold()
        icon_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "anthropic-tunnel/icons"
        icon_dir.mkdir(parents=True, exist_ok=True)
        for state, data in core.ICONS.items():
            (icon_dir / f"anthropic-tunnel-{state}.png").write_bytes(base64.b64decode(data))
        self.indicator = AppIndicator.Indicator.new(
            "anthropic-tunnel", "anthropic-tunnel-grey", AppIndicator.IndicatorCategory.SYSTEM_SERVICES)
        self.indicator.set_icon_theme_path(str(icon_dir))
        self.indicator.set_title("Anthropic Tunnel")
        self.menu = Gtk.Menu()
        self.status = self.add_item(self.menu, "Checking tunnel…")
        self.menu.append(Gtk.SeparatorMenuItem())
        self.connect_item = self.add_item(self.menu, "Connect", "connect")
        self.disconnect_item = self.add_item(self.menu, "Disconnect (allow direct access)", "disconnect")
        self.restart_item = self.add_item(self.menu, "Restart tunnel", "restart")
        self.transport_menu = Gtk.Menu()
        self.transport_item = self.add_item(self.menu, "Transport")
        self.transport_item.set_submenu(self.transport_menu)
        self.transports = None
        self.stats_menu = Gtk.Menu()
        self.stats_item = self.add_item(self.menu, "Stats")
        self.stats_item.set_sensitive(True)
        self.stats_item.set_submenu(self.stats_menu)
        self.upload = self.add_item(self.stats_menu, "Session upload: —")
        self.download = self.add_item(self.stats_menu, "Session download: —")
        self.rates = self.add_item(self.stats_menu, "Current rate: —")
        self.connections = self.add_item(self.stats_menu, "Active Anthropic connections: —")
        self.menu.append(Gtk.SeparatorMenuItem())
        self.add_item(self.menu, "Open log", "log")
        self.add_item(self.menu, "Copy diagnostics", "diag")
        self.add_item(self.menu, "Flush DNS cache", "flushdns")
        self.menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Quit indicator (keep tunnel running)")
        quit_item.connect("activate", lambda *_: self.stop())
        self.menu.append(quit_item)
        self.menu.show_all()
        self.indicator.set_menu(self.menu)
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.timer = GLib.timeout_add_seconds(5, self.refresh)
        self.refresh()

    def add_item(self, menu, label, action=None, arg=None):
        item = Gtk.MenuItem(label=label)
        item.set_sensitive(action is not None)
        if action:
            item.connect("activate", lambda *_: self.run_action(action, arg))
        menu.append(item)
        return item

    def background(self, action=None, arg=None):
        if self.busy or self.closing:
            return
        self.busy = True

        def worker():
            error = None
            result = None
            try:
                if action in ("connect", "disconnect", "restart"):
                    script = {"connect": "tunnel-up.sh", "disconnect": "tunnel-down.sh",
                              "restart": "tunnel-restart.sh"}[action]
                    completed = subprocess.run(["sudo", "-n", core.BIN + "/" + script],
                                               capture_output=True, text=True, timeout=35)
                    if completed.returncode:
                        raise RuntimeError(completed.stderr.strip() or "Tunnel control failed")
                elif action == "transport":
                    core.api("/proxies/anthropic", "PUT", {"name": arg})
                elif action:
                    core.do_action(action, arg)
                result = core.gather()
            except Exception as exc:
                error = str(exc)
            GLib.idle_add(self.finish, result, error, bool(action))

        threading.Thread(target=worker, daemon=True).start()

    def refresh(self):
        self.background()
        return GLib.SOURCE_CONTINUE

    def run_action(self, action, arg):
        if self.busy:
            self.pending_action = (action, arg)
            return
        self.background(action, arg)

    def finish(self, result, error, action_requested):
        self.busy = False
        if self.closing:
            return GLib.SOURCE_REMOVE
        if error:
            self.status.set_label("Indicator error: " + error[:160])
            self.indicator.set_icon_full("anthropic-tunnel-grey", "Status unavailable")
            self.indicator.set_label("?", "↓999M")
            if action_requested:
                core.notify("Anthropic Tunnel", error[:200])
        if result:
            self.update(*result)
        if self.pending_action:
            action, arg = self.pending_action
            self.pending_action = None
            self.background(action, arg)
        return GLib.SOURCE_REMOVE

    def update(self, state, label, info):
        self.indicator.set_icon_full("anthropic-tunnel-" + state, "Anthropic Tunnel")
        self.indicator.set_label(label, "↓999M")
        if not info["loaded"]:
            status = "Disabled: Anthropic traffic goes DIRECT"
        elif not info["running"] or not info["api"]:
            status = "Daemon stopped, starting, or API unreachable"
        elif state == "red":
            status = f"Tunnel DOWN via {info['selector']}: Anthropic traffic BLOCKED"
        else:
            uptime = core.fmt_uptime(time.time() - info["started"]) if info.get("started") else "—"
            status = f"Connected via {info['selector']} · {info['delay']} ms · up {uptime}"
        self.status.set_label(status)
        self.connect_item.set_sensitive(not info["loaded"])
        self.disconnect_item.set_sensitive(info["loaded"])
        self.restart_item.set_sensitive(info["loaded"])
        transports = (tuple(info["all"]), info["selector"])
        if transports != self.transports:
            for child in self.transport_menu.get_children():
                child.destroy()
            for transport in info["all"]:
                title = ("✓ " if transport == info["selector"] else "") + transport
                self.add_item(self.transport_menu, title, "transport", transport)
            self.transport_menu.show_all()
            self.transports = transports
        self.transport_item.set_sensitive(bool(info["all"]))
        self.upload.set_label("Session upload: " + core.human(info.get("sess_up", 0)))
        self.download.set_label("Session download: " + core.human(info.get("sess_down", 0)))
        self.rates.set_label(f"Current rate: ↑{core.rate(info['rate_up'])} ↓{core.rate(info['rate_down'])}")
        self.connections.set_label(f"Active Anthropic connections: {len(info['conns'])}")

    def stop(self):
        self.closing = True
        if self.timer:
            GLib.source_remove(self.timer)
        if self.indicator:
            self.indicator.set_status(AppIndicator.IndicatorStatus.PASSIVE)
        self.quit()


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        print("GTK 3 and AppIndicator available; shared tunnel backend loaded.")
    elif sys.argv[1:] == ["--quit"]:
        app = TunnelIndicator()
        app.register(None)
        if app.get_is_remote():
            app.activate_action("quit", None)
    else:
        app = TunnelIndicator()
        sys.exit(app.run(sys.argv))

#!/usr/bin/env python3
"""Print unread counts that apps publish over D-Bus, one JSON line per change.

Apps such as Telegram and Electron apps send their unread count as a
com.canonical.Unity.LauncherEntry "Update" signal, naming themselves by their
desktop file ("application://org.telegram.desktop.desktop"). Each line printed
is {"app": "<desktop id without .desktop>", "count": n, "visible": bool}.

Some apps (Telegram among them) only send counts when a launcher owns the
com.canonical.Unity bus name, as Unity and KDE Plasma do, so this claims it.
"""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

state = {}


def on_update(_conn, _sender, _path, _iface, _signal, params):
    try:
        uri, props = params.unpack()
    except (TypeError, ValueError):
        return
    if not isinstance(uri, str) or not uri.startswith("application://"):
        return
    app = uri[len("application://"):]
    if app.endswith(".desktop"):
        app = app[: -len(".desktop")]
    entry = state.setdefault(app, {"count": 0, "visible": False})
    changed = False
    count = props.get("count")
    if isinstance(count, (int, float)) and not isinstance(count, bool):
        entry["count"] = int(count)
        changed = True
    visible = props.get("count-visible")
    if isinstance(visible, bool):
        entry["visible"] = visible
        changed = True
    if changed:
        print(json.dumps({"app": app, **entry}), flush=True)


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.signal_subscribe(
        None, "com.canonical.Unity.LauncherEntry", "Update", None, None,
        Gio.DBusSignalFlags.NONE, on_update,
    )
    # Not fatal if something else already owns it; the signals still arrive.
    Gio.bus_own_name_on_connection(bus, "com.canonical.Unity", Gio.BusNameOwnerFlags.NONE, None, None)
    GLib.MainLoop().run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)

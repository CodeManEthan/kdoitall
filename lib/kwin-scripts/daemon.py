#!/usr/bin/env python3
"""kdoitall snapshot daemon — long-lived KWin-script-driven window snapshot service.

Registers org.kdoitall.Snapshot on the session bus. Exposes:
  TakeSnapshot(int timeout_ms) -> string (JSON payload)
  Deliver(string payload)         — called BY the KWin script

A single instance serves all kdoitall calls; lib/kwin-scripts/snapshot.sh
auto-spawns it on first use. The daemon stays alive for the session and
dies cleanly when the session bus closes (or on SIGTERM/SIGINT).

The bash client serializes concurrent calls via flock, so the daemon
handles one in-flight TakeSnapshot at a time. Subsequent calls during an
in-flight request are rejected with "daemon busy" — the bash flock should
prevent this from being observable in practice.
"""

import os
import signal
import sys

import dbus
import dbus.exceptions
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.kdoitall.Snapshot"
OBJECT_PATH = "/Snapshot"
INTERFACE = "org.kdoitall.Snapshot"
KWIN_SERVICE = "org.kde.KWin"
KWIN_PATH = "/Scripting"
KWIN_IFACE = "org.kde.kwin.Scripting"


class SnapshotDaemon(dbus.service.Object):
    def __init__(self, bus_name, path, js_file):
        super().__init__(bus_name, path)
        self._js_file = js_file
        self._counter = 0
        # Single in-flight request (the bash client serializes via flock):
        self._reply_cb = None
        self._error_cb = None
        self._plugin_name = None
        self._timeout_source = None

    def _kwin(self):
        bus = dbus.SessionBus()
        return dbus.Interface(bus.get_object(KWIN_SERVICE, KWIN_PATH), KWIN_IFACE)

    def _unload(self, plugin_name):
        if not plugin_name:
            return
        try:
            self._kwin().unloadScript(plugin_name)
        except Exception:
            pass

    def _clear_pending(self):
        if self._timeout_source:
            GLib.source_remove(self._timeout_source)
        self._reply_cb = None
        self._error_cb = None
        self._plugin_name = None
        self._timeout_source = None

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="")
    def Deliver(self, payload):
        if self._reply_cb is None:
            # Stale Deliver (e.g., a script that finished after its caller
            # timed out). Drop silently.
            return
        reply = self._reply_cb
        plugin_name = self._plugin_name
        self._clear_pending()
        try:
            reply(payload)
        finally:
            self._unload(plugin_name)

    @dbus.service.method(
        INTERFACE,
        in_signature="i",
        out_signature="s",
        async_callbacks=("_reply", "_error"),
    )
    def TakeSnapshot(self, timeout_ms, _reply, _error):
        if self._reply_cb is not None:
            _error(dbus.exceptions.DBusException("daemon busy"))
            return

        self._counter += 1
        plugin_name = "kdoitall-snapshot-%d-%d" % (os.getpid(), self._counter)
        self._reply_cb = _reply
        self._error_cb = _error
        self._plugin_name = plugin_name

        def on_timeout():
            self._timeout_source = None
            err = self._error_cb
            pn = self._plugin_name
            self._clear_pending()
            self._unload(pn)
            if err:
                err(dbus.exceptions.DBusException("snapshot timeout"))
            return False  # one-shot

        self._timeout_source = GLib.timeout_add(timeout_ms, on_timeout)

        try:
            kwin = self._kwin()
            # KWin exposes two loadScript overloads (1-arg and 2-arg); we want
            # the 2-arg form so we can pass our unique pluginName, but
            # dbus-python's introspection-based dispatch picks the 1-arg form
            # by default. Force the signature.
            kwin.loadScript(self._js_file, plugin_name, signature="ss")
            kwin.start()
        except dbus.exceptions.DBusException as e:
            err = self._error_cb
            self._clear_pending()
            if err:
                err(dbus.exceptions.DBusException("kwin load/start failed: %s" % e))


def main():
    if len(sys.argv) < 2:
        print("usage: daemon.py <path-to-snapshot.js>", file=sys.stderr)
        sys.exit(2)

    js_file = sys.argv[1]
    if not os.path.isfile(js_file):
        print("snapshot.js not found at: %s" % js_file, file=sys.stderr)
        sys.exit(2)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    try:
        bus_name = dbus.service.BusName(
            BUS_NAME, bus, replace_existing=False, do_not_queue=True
        )
    except dbus.exceptions.NameExistsException:
        # Another daemon already owns the name — that's fine, just exit.
        print("daemon already running", file=sys.stderr)
        sys.exit(0)

    SnapshotDaemon(bus_name, OBJECT_PATH, js_file)

    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()

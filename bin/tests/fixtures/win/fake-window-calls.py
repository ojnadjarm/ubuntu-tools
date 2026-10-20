#!/usr/bin/env python3
"""Fake Window Calls extension (org.gnome.Shell /org/gnome/Shell/Extensions/Windows) on a private bus: argv fixture JSON, call log."""
import json, sys, warnings
warnings.simplefilter("ignore", DeprecationWarning)
from gi.repository import Gio, GLib

XML = """<node><interface name="org.gnome.Shell.Extensions.Windows">
 <method name="List"><arg type="s" direction="out"/></method>
 <method name="Details"><arg type="u" direction="in"/><arg type="s" direction="out"/></method>
 <method name="Activate"><arg type="u" direction="in"/></method>
 <method name="Close"><arg type="u" direction="in"/></method>
 <method name="Minimize"><arg type="u" direction="in"/></method>
 <method name="Maximize"><arg type="u" direction="in"/></method>
 <method name="Move"><arg type="u" direction="in"/><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
 <method name="Resize"><arg type="u" direction="in"/><arg type="u" direction="in"/><arg type="u" direction="in"/></method>
</interface></node>"""
fx = json.load(open(sys.argv[1]))
log = open(sys.argv[2], "a", buffering=1)


def on_call(conn, sender, path, iface, method, params, inv):
    args = params.unpack()
    log.write(" ".join([method] + [str(a) for a in args]) + "\n")
    if method == "List":
        return inv.return_value(GLib.Variant("(s)", (json.dumps(fx["list"]),)))
    if method == "Details":
        return inv.return_value(GLib.Variant("(s)", (json.dumps(fx["details"][str(args[0])]),)))
    if method == "Activate" and args[0] not in fx["stuck"]:
        for w in fx["list"]:
            w["focus"] = w["id"] == args[0]
    inv.return_value(None)


def on_bus(conn, name):
    conn.register_object("/org/gnome/Shell/Extensions/Windows",
                         Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], on_call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.gnome.Shell", 0, on_bus, None, None)
GLib.MainLoop().run()

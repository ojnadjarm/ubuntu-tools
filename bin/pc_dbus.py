#!/usr/bin/env python3
"""pc_dbus.py index --bus user|system|a11y — one TSV row per bus member, for `pc dbus find`.

Columns: bus, name, path, interface, member, kind (interface|method|property|signal).
One process walks every well-known name with Gio; unreachable names are skipped.
"""
import sys
import xml.etree.ElementTree as ET

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

TIMEOUT = 400
STD = "org.freedesktop.DBus."


def connect(bus):
    if bus == "system":
        return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    if bus == "user":
        return Gio.bus_get_sync(Gio.BusType.SESSION, None)
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    addr = session.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus",
                             "GetAddress", None, None, 0, TIMEOUT, None).unpack()[0]
    return Gio.DBusConnection.new_for_address_sync(
        addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None)


def introspect(conn, name, path):
    try:
        return conn.call_sync(name, path, STD + "Introspectable", "Introspect",
                              None, GLib.VariantType("(s)"), 0, TIMEOUT, None).unpack()[0]
    except GLib.Error:
        return None


def walk(conn, bus, name, path, out, seen, shapes=None):
    # Objects that repeat one interface set (systemd's 380 unit objects) are listed once.
    if path in seen or len(seen) > 2000:
        return
    seen.add(path)
    xml = introspect(conn, name, path)
    if not xml:
        return
    try:
        node = ET.fromstring(xml)
    except ET.ParseError:
        return
    if shapes is None:
        shapes = set()
    shape = frozenset(i.get("name", "") for i in node.findall("interface"))
    fresh = shape not in shapes
    shapes.add(shape)
    for iface in node.findall("interface") if fresh else ():
        iname = iface.get("name", "")
        if iname.startswith(STD):
            continue
        out.append((bus, name, path, iname, "", "interface"))
        for tag, kind in (("method", "method"), ("property", "property"), ("signal", "signal")):
            for m in iface.findall(tag):
                out.append((bus, name, path, iname, m.get("name", ""), kind))
    for child in node.findall("node"):
        sub = child.get("name")
        if sub:
            walk(conn, bus, name, (path.rstrip("/") + "/" + sub), out, seen, shapes)


def main():
    bus = "user"
    if "--bus" in sys.argv:
        bus = sys.argv[sys.argv.index("--bus") + 1]
    conn = connect(bus)
    names = conn.call_sync(STD[:-1], "/org/freedesktop/DBus", STD[:-1], "ListNames",
                           None, GLib.VariantType("(as)"), 0, TIMEOUT, None).unpack()[0]
    # One connection can own many well-known names; walk it once, under its shortest name.
    best = {}
    for name in sorted(n for n in names if not n.startswith(":")):
        try:
            owner = conn.call_sync(STD[:-1], "/org/freedesktop/DBus", STD[:-1], "GetNameOwner",
                                   GLib.Variant("(s)", (name,)), GLib.VariantType("(s)"),
                                   0, TIMEOUT, None).unpack()[0]
        except GLib.Error:
            owner = name
        if owner not in best or (len(name), name) < (len(best[owner]), best[owner]):
            best[owner] = name
    out = []
    for name in sorted(best.values()):
        walk(conn, bus, name, "/", out, set())
    sys.stdout.write("".join("\t".join(r) + "\n" for r in out))


if __name__ == "__main__":
    main()

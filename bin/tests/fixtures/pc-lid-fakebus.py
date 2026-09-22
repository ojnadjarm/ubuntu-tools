#!/usr/bin/env python3
"""Fake UPower + mutter DisplayConfig on a private bus; drives pc_lid.py through a lid close, a gsd reset and a lid open."""
import json, os, signal, subprocess, sys, warnings
warnings.simplefilter('ignore', DeprecationWarning)
from gi.repository import Gio, GLib

XML = '''<node>
<interface name="org.freedesktop.UPower"><property name="LidIsClosed" type="b" access="read"/></interface>
<interface name="org.gnome.Mutter.DisplayConfig">
 <property name="PowerSaveMode" type="i" access="readwrite"/>
 <property name="HasExternalMonitor" type="b" access="read"/>
 <signal name="MonitorsChanged"/>
</interface></node>'''
st = {'LidIsClosed': GLib.Variant('b', False), 'PowerSaveMode': GLib.Variant('i', 0), 'HasExternalMonitor': GLib.Variant('b', False)}
IFACE = {'LidIsClosed': 'org.freedesktop.UPower'}
PATH = {'org.freedesktop.UPower': '/org/freedesktop/UPower', 'org.gnome.Mutter.DisplayConfig': '/org/gnome/Mutter/DisplayConfig'}
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
node = Gio.DBusNodeInfo.new_for_xml(XML)

def change(prop, v):
    st[prop] = v
    iface = IFACE.get(prop, 'org.gnome.Mutter.DisplayConfig')
    bus.emit_signal(None, PATH[iface], 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                    GLib.Variant('(sa{sv}as)', (iface, {prop: v}, [])))

def get_prop(c, s, p, i, prop): return st[prop]
def set_prop(c, s, p, i, prop, v): change(prop, v); return True
for iface in node.interfaces:
    bus.register_object(PATH[iface.name], iface, None, get_prop, set_prop)
for name in PATH:
    bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName',
                  GLib.Variant('(su)', (name, 0)), None, 0, 2000, None)

state_file = os.path.join(os.environ['XDG_RUNTIME_DIR'], 'pc-lid.json')
w = subprocess.Popen([sys.executable, os.path.join(sys.argv[1], 'pc_lid.py')])
psm = lambda: st['PowerSaveMode'].unpack()
got, loop = [], GLib.MainLoop()
steps = [
    (lambda: change('LidIsClosed', GLib.Variant('b', True)), lambda: ('lid closes: psm 3', psm(), 3)),
    (lambda: change('PowerSaveMode', GLib.Variant('i', 0)), lambda: ('gsd resets to 0: reasserted 3', psm(), 3)),
    (lambda: None, lambda: ('reasserts counted', json.load(open(state_file))['reasserts'], 1)),
    (lambda: change('HasExternalMonitor', GLib.Variant('b', True)), lambda: ('TV connected while closed: psm 0', psm(), 0)),
    (lambda: change('HasExternalMonitor', GLib.Variant('b', False)), lambda: ('TV gone again: psm 3', psm(), 3)),
    (lambda: change('LidIsClosed', GLib.Variant('b', False)), lambda: ('lid opens: psm 0', psm(), 0)),
]
def step(i=[0]):
    if i[0] > 0:
        got.append(steps[i[0] - 1][1]())
    if i[0] == len(steps):
        loop.quit(); return False
    steps[i[0]][0](); i[0] += 1
    return True
GLib.timeout_add(300, step)
GLib.timeout_add(8000, loop.quit)
loop.run()
w.send_signal(signal.SIGTERM)
got.append(('SIGTERM: watcher exits 0', w.wait(3), 0))
bad = 0
for name, g, want in got:
    print(('ok   ' if g == want else 'FAIL ') + name + ('' if g == want else f': expected {want!r}, got {g!r}'))
    bad |= g != want
sys.exit(1 if bad or len(got) != len(steps) + 1 else 0)

import sys, os, shutil, urllib.parse
from gi.repository import Gio, GLib
out = sys.argv[1]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
sender = bus.get_unique_name()[1:].replace('.', '_')
token = 'shot%d' % os.getpid()
path = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
loop = GLib.MainLoop(); result = {}
def on_resp(conn, s, p, iface, sig, params):
    result['code'], result['res'] = params.unpack(); loop.quit()
bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response', path, None, 0, on_resp)
bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop', 'org.freedesktop.portal.Screenshot', 'Screenshot',
    GLib.Variant('(sa{sv})', ('', {'interactive': GLib.Variant('b', False), 'handle_token': GLib.Variant('s', token)})),
    None, 0, -1, None)
GLib.timeout_add_seconds(20, loop.quit); loop.run()
if result.get('code') != 0: sys.exit(f'portal failed: {result}')
src = urllib.parse.unquote(result['res']['uri'].replace('file://', ''))
shutil.move(src, out); print(out)

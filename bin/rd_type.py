# Type text via mutter RemoteDesktop keysyms (keyboard-layout independent).
import sys, time, subprocess
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
D='org.gnome.Mutter.RemoteDesktop'
call = lambda p, i, m, a=None: bus.call_sync(D, p, i, m, a, None, 0, -1, None)
(sess,) = call('/org/gnome/Mutter/RemoteDesktop', D, 'CreateSession').unpack()
SI = D + '.Session'; call(sess, SI, 'Start')
SPECIAL = {'\n': 28, '\t': 15}  # evdev keycodes
for ch in sys.argv[1]:
    if ch in SPECIAL:
        subprocess.run(['ydotool', 'key', f'{SPECIAL[ch]}:1', f'{SPECIAL[ch]}:0']); continue
    ks = ord(ch) if 0x20 <= ord(ch) <= 0xff else 0x01000000 | ord(ch)
    call(sess, SI, 'NotifyKeyboardKeysym', GLib.Variant('(ub)', (ks, True)))
    call(sess, SI, 'NotifyKeyboardKeysym', GLib.Variant('(ub)', (ks, False)))
    time.sleep(0.02)
time.sleep(0.1); call(sess, SI, 'Stop')

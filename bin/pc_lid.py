#!/usr/bin/env python3
"""pc lid watch — lid closed with no external monitor: mutter PowerSaveMode 3; otherwise 0."""
import json
import os
import signal
import subprocess
import sys
import time

DARK, LIT = 3, 0
FLOOD_N, FLOOD_S = 5, 10
UP = ('org.freedesktop.UPower', '/org/freedesktop/UPower', 'org.freedesktop.UPower')
DC = ('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig', 'org.gnome.Mutter.DisplayConfig')
STATE = os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'pc-lid.json')


class Lid:
    """Decide PowerSaveMode on every event; reassert DARK when something resets it while dark is wanted."""

    def __init__(self, bus, state_path=STATE, notify=None, clock=time.monotonic):
        self.bus, self.state_path, self.clock = bus, state_path, clock
        self.notify = notify or (lambda msg: subprocess.run(['notify-owner', msg], check=False))
        self.we_set, self.gave_up, self.reasserts, self.sets = False, False, 0, []

    def evaluate(self):
        closed, ext, psm = self.bus.lid_closed(), self.bus.external(), self.bus.psm()
        if closed and not ext:
            if psm == DARK or self.gave_up:
                return None
            now = self.clock()
            self.sets = [t for t in self.sets if now - t < FLOOD_S] + [now]
            if len(self.sets) > FLOOD_N:
                self.gave_up = True
                self.notify(f'pc lid: PowerSaveMode reset {FLOOD_N}+ times in {FLOOD_S}s; stopped reasserting until the lid opens')
                self.save('gave-up')
                return None
            if self.we_set:
                self.reasserts += 1
            self.bus.set_psm(DARK)
            self.we_set = True
            self.save('dark')
            return DARK
        self.gave_up = False
        if psm == DARK and (self.we_set or not closed):
            self.bus.set_psm(LIT)
            self.we_set = False
            self.save('lit')
            return LIT
        self.we_set = False
        return None

    def save(self, last):
        try:
            with open(self.state_path, 'w') as f:
                json.dump({'last': last, 'reasserts': self.reasserts, 'we_set': self.we_set,
                           'ts': int(time.time()), 'pid': os.getpid()}, f)
        except OSError:
            pass


class GioBus:
    """The real buses: UPower on the system bus, mutter DisplayConfig on the session bus."""

    def __init__(self):
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.sys = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        self.ses = Gio.bus_get_sync(Gio.BusType.SESSION)

    def _get(self, conn, obj, prop):
        r = conn.call_sync(obj[0], obj[1], 'org.freedesktop.DBus.Properties', 'Get',
                           self.GLib.Variant('(ss)', (obj[2], prop)), self.GLib.VariantType('(v)'),
                           self.Gio.DBusCallFlags.NONE, 2000, None)
        return r.unpack()[0]

    def lid_closed(self):
        return bool(self._get(self.sys, UP, 'LidIsClosed'))

    def external(self):
        return bool(self._get(self.ses, DC, 'HasExternalMonitor'))

    def psm(self):
        return int(self._get(self.ses, DC, 'PowerSaveMode'))

    def set_psm(self, v):
        V = self.GLib.Variant
        self.ses.call_sync(DC[0], DC[1], 'org.freedesktop.DBus.Properties', 'Set',
                           V('(ssv)', (DC[2], 'PowerSaveMode', V('i', v))), None,
                           self.Gio.DBusCallFlags.NONE, 2000, None)

    def run(self, lid):
        loop, err = self.GLib.MainLoop(), []

        def on_event(*_):
            try:
                lid.evaluate()
            except Exception as e:  # a bus error ends the run; systemd restarts it
                err.append(e)
                loop.quit()

        props = 'org.freedesktop.DBus.Properties'
        self.sys.signal_subscribe(UP[0], props, 'PropertiesChanged', UP[1], None, 0, on_event)
        self.ses.signal_subscribe(DC[0], props, 'PropertiesChanged', DC[1], None, 0, on_event)
        self.ses.signal_subscribe(DC[0], DC[2], 'MonitorsChanged', DC[1], None, 0, on_event)
        try:
            from gi.repository import GLibUnix
            sig_add = GLibUnix.signal_add
        except ImportError:
            sig_add = self.GLib.unix_signal_add
        for s in (signal.SIGTERM, signal.SIGINT):
            sig_add(self.GLib.PRIORITY_DEFAULT, s, loop.quit)
        on_event()
        if not err:
            loop.run()
        if lid.we_set:
            try:
                self.set_psm(LIT)
            except Exception:
                pass
        if err:
            print(f'pc lid watch: {err[0]}', file=sys.stderr)
            return 1
        return 0


if __name__ == '__main__':
    bus = GioBus()
    sys.exit(bus.run(Lid(bus)))

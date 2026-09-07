#!/usr/bin/env python3
"""pc_input.py — evdev view of the input stack: devices, capabilities, live watch, fd holders, uinput inject.

Reads parse $PC_PROC (default /proc) so a captured tree in tests/fixtures/input/ replays them;
`caps`, `watch` and the inject read-back need the real nodes and run under sudo -n from pc-input.
Injection creates its own `pc-input-virtual` uinput device, writes, reads the events back from
that device's own node through a short root reader, then destroys it — the "verified" half of
the one-verified-action rule. --device-only makes the reader EVIOCGRAB the node first, so the
events never reach libinput/gnome-shell (the only form that is safe at night).
"""
import argparse
import fcntl
import json
import os
import select
import subprocess
import sys
import time

EVIOCGRAB = 0x40044590
VIRTUAL_NAME = "pc-input-virtual"
# Openers every evdev node has: they multiplex, they never grab.
MULTIPLEXERS = {"systemd", "systemd-logind", "gnome-shell", "upowerd"}
SELF = os.path.realpath(__file__)


def readable(fd, deadline):
    """True while fd has data to read before the deadline (time.monotonic)."""
    left = deadline - time.monotonic()
    return left > 0 and bool(select.select([fd], [], [], left)[0])


def proc_root():
    return os.environ.get("PC_PROC", "/proc")


def read_file(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def ev_names(mask_hex):
    """EV=<hex> bitmask -> the EV_* type names it carries."""
    from evdev import ecodes
    try:
        mask = int(mask_hex, 16)
    except (TypeError, ValueError):
        return []
    out = []
    for bit in range(0, 32):
        if mask & (1 << bit):
            out.append(ecodes.EV.get(bit, "EV_%d" % bit))
    return out


def parse_devices():
    """/proc/bus/input/devices -> one dict per node."""
    text = read_file(proc_root() + "/bus/input/devices") or ""
    devs = []
    cur = {}
    for line in text.splitlines() + [""]:
        if not line.strip():
            if cur.get("handlers"):
                devs.append(cur)
            cur = {}
            continue
        tag, _, rest = line.partition(": ")
        if tag == "I":
            for f in rest.split():
                k, _, v = f.partition("=")
                cur[k.lower()] = v
        elif tag == "N":
            cur["name"] = rest.partition("=")[2].strip('"')
        elif tag == "P":
            cur["phys"] = rest.partition("=")[2]
        elif tag == "S":
            cur["sysfs"] = rest.partition("=")[2]
        elif tag == "U":
            cur["uniq"] = rest.partition("=")[2]
        elif tag == "H":
            cur["handlers"] = rest.partition("=")[2].split()
        elif tag == "B":
            k, _, v = rest.partition("=")
            if k == "EV":
                cur["ev"] = ev_names(v.split()[-1] if v.split() else "0")
    out = []
    for d in devs:
        node = next((h for h in d["handlers"] if h.startswith("event")), None)
        out.append({
            "path": "/dev/input/" + node if node else None,
            "name": d.get("name", ""),
            "bus": d.get("bus", ""),
            "vendor": d.get("vendor", ""),
            "product": d.get("product", ""),
            "version": d.get("version", ""),
            "phys": d.get("phys", ""),
            "sysfs": d.get("sysfs", ""),
            "uniq": d.get("uniq", ""),
            "handlers": d["handlers"],
            "ev": d.get("ev", []),
        })
    return out


def unit_of(pid):
    """The systemd unit owning a pid, from its cgroup path."""
    text = read_file("%s/%s/cgroup" % (proc_root(), pid)) or ""
    for line in text.splitlines():
        path = line.rpartition(":")[2]
        for part in reversed(path.split("/")):
            if part.endswith((".service", ".scope", ".slice")):
                return part
    return ""


def holders():
    """node path -> list of {pid, comm, unit, sidecar} holding an fd on it."""
    root = proc_root()
    out = {}
    for pid in os.listdir(root):
        if not pid.isdigit():
            continue
        fddir = "%s/%s/fd" % (root, pid)
        try:
            fds = os.listdir(fddir)
        except OSError:
            continue
        seen = set()
        for fd in fds:
            try:
                target = os.readlink("%s/%s" % (fddir, fd))
            except OSError:
                continue
            if not target.startswith("/dev/input/event") or target in seen:
                continue
            seen.add(target)
            unit = unit_of(pid)
            out.setdefault(target, []).append({
                "pid": int(pid),
                "comm": (read_file("%s/%s/comm" % (root, pid)) or "").strip(),
                "unit": unit,
                "sidecar": unit == "dark-eye-ptt.service",
            })
    return out


def cmd_devices(args):
    hold = holders()
    devs = parse_devices()
    for d in devs:
        hs = hold.get(d["path"], [])
        d["openers"] = sorted(hs, key=lambda h: h["pid"])
        # A grab is not readable from userspace; a holder that is not one of the known
        # multiplexers is the only evidence there is (the sidecar names itself).
        d["grabbed_guess"] = any(h["comm"] not in MULTIPLEXERS for h in hs)
    if args.json:
        json.dump(devs, sys.stdout)
        sys.stdout.write("\n")
        return 0
    for d in devs:
        who = ",".join(h["comm"] for h in d["openers"]) or "-"
        print("%-18s %-34s bus %s %s:%s  %-14s %s%s" % (
            d["path"] or "-", d["name"][:34], d["bus"], d["vendor"], d["product"],
            "+".join(t[3:].lower() for t in d["ev"])[:14], who,
            "  GRAB?" if d["grabbed_guess"] else ""))
    return 0


def cmd_grabs(args):
    hold = holders()
    names = {d["path"]: d["name"] for d in parse_devices()}
    rows = []
    for node in sorted(hold):
        hs = sorted(hold[node], key=lambda h: h["pid"])
        rows.append({
            "path": node,
            "name": names.get(node, ""),
            "openers": hs,
            "grabbed_guess": any(h["comm"] not in MULTIPLEXERS for h in hs),
            "sidecar": any(h["sidecar"] for h in hs),
        })
    if args.json:
        json.dump(rows, sys.stdout)
        sys.stdout.write("\n")
        return 0
    for r in rows:
        print("%-18s %-30s %s%s" % (
            r["path"], r["name"][:30],
            ",".join("%s(%d)" % (h["comm"], h["pid"]) for h in r["openers"]),
            "  SIDECAR" if r["sidecar"] else ("  GRAB?" if r["grabbed_guess"] else "")))
    return 0


def name_of(etype, code):
    from evdev import ecodes
    n = ecodes.bytype.get(etype, {}).get(code, str(code))
    return n[0] if isinstance(n, (list, tuple)) else n


def open_device(path):
    from evdev import InputDevice
    try:
        return InputDevice(path)
    except OSError as ex:
        sys.stderr.write("pc input: cannot open %s: %s\n" % (path, ex))
        sys.exit(1)


def cmd_caps(args):
    from evdev import ecodes
    dev = open_device(args.device)
    caps = {}
    for etype, codes in dev.capabilities(absinfo=True).items():
        entries = []
        for c in codes:
            if isinstance(c, tuple):
                code, info = c
                entries.append({"code": code, "name": name_of(etype, code),
                                "min": info.min, "max": info.max, "fuzz": info.fuzz,
                                "flat": info.flat, "resolution": info.resolution})
            else:
                entries.append({"code": c, "name": name_of(etype, c)})
        caps[ecodes.EV.get(etype, str(etype))] = entries
    out = {"path": dev.path, "name": dev.name, "phys": dev.phys,
           "bus": dev.info.bustype, "vendor": dev.info.vendor, "product": dev.info.product,
           "capabilities": caps}
    if args.json:
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
    else:
        print("%s  %s  (bus %#x vendor %04x product %04x)" % (
            out["path"], out["name"], out["bus"], out["vendor"], out["product"]))
        for etype, entries in caps.items():
            names = ", ".join(e["name"] + (" [%d..%d]" % (e["min"], e["max"]) if "min" in e else "")
                              for e in entries)
            print("  %-8s %s" % (etype, names))
    dev.close()
    return 0


def cmd_watch(args):
    """NDJSON of raw events for --seconds, with a hard deadline; 0 events is a valid result."""
    from evdev import ecodes
    dev = open_device(args.device)
    deadline = time.monotonic() + args.seconds
    n = 0
    try:
        while True:
            if not readable(dev.fd, deadline):
                break
            for ev in dev.read():
                n += 1
                row = {"sec": round(ev.timestamp(), 6), "type": ecodes.EV.get(ev.type, str(ev.type)),
                       "code": name_of(ev.type, ev.code), "value": ev.value}
                if args.json:
                    print(json.dumps(row), flush=True)
                else:
                    print("%.6f %-8s %-22s %d" % (row["sec"], row["type"], row["code"], row["value"]),
                          flush=True)
    except OSError as ex:
        sys.stderr.write("pc input watch: %s\n" % ex)
        return 1
    finally:
        dev.close()
    if not args.json:
        print("%d events in %.1fs on %s" % (n, args.seconds, args.device))
    return 0


def cmd_readback(args):
    """Internal: open <device>, optionally grab it, announce ready, print events as NDJSON."""
    dev = open_device(args.device)
    if args.grab:
        # Never steal a node the ptt sidecar holds exclusively (KB quirks: the XM5 AVRCP node).
        if any(h["sidecar"] for h in holders().get(args.device, [])):
            sys.stderr.write("pc input: refused — %s is held by dark-eye-ptt.service\n" % args.device)
            return 3
        fcntl.ioctl(dev.fd, EVIOCGRAB, 1)
    print(json.dumps({"ready": True}), flush=True)
    deadline = time.monotonic() + args.seconds
    seen = 0
    while seen < args.count:
        if not readable(dev.fd, deadline):
            break
        try:
            for ev in dev.read():
                if ev.type == 0:          # EV_SYN is framing, not a change
                    continue
                print(json.dumps([ev.type, ev.code, ev.value]), flush=True)
                seen += 1
        except OSError:
            break
    dev.close()
    return 0


def resolve(kind, name):
    """A KEY_/REL_/ABS_ name or a raw numeric code -> (ev type, code)."""
    from evdev import ecodes
    etype = {"key": ecodes.EV_KEY, "rel": ecodes.EV_REL, "abs": ecodes.EV_ABS}[kind]
    if name.isdigit():
        return etype, int(name)
    code = ecodes.ecodes.get(name.upper())
    if code is None:
        sys.stderr.write("pc input: unknown %s name %s\n" % (kind, name))
        sys.exit(2)
    return etype, code


def plan(args):
    """The events this injection would emit, plus the ledger's target/before/after strings."""
    from evdev import ecodes
    etype, code = resolve(args.kind, args.name)
    cname = name_of(etype, code)
    if args.kind == "key":
        if args.value is None:
            events = [(etype, code, 1), (etype, code, 0)]
            before, after = "up", "down,up"
        else:
            events = [(etype, code, args.value)]
            before = "down" if args.value == 0 else "up"
            after = "down" if args.value == 1 else "up"
        target = "key:" + cname
    else:
        value = args.value if args.value is not None else 1
        events = [(etype, code, value)]
        target = "%s:%s" % (args.kind, cname)
        before, after = "0", "%+d" % value if args.kind == "rel" else str(value)
    return {"target": target, "before": before, "after": after,
            "events": [{"type": ecodes.EV.get(t, str(t)), "code": name_of(t, c), "value": v}
                       for t, c, v in events],
            "raw": events, "device_only": args.device_only}


def node_of(ui):
    """The event node the kernel gave our uinput fd, from UI_GET_SYSNAME."""
    from evdev import _uinput
    syspath = "/sys/devices/virtual/input/" + _uinput.get_sysname(ui.fd)
    for _ in range(50):                        # devtmpfs is immediate; udev may lag a tick
        for child in sorted(os.listdir(syspath)):
            if child.startswith("event"):
                return "/dev/input/" + child
        time.sleep(0.02)
    return None


def cmd_inject(args):
    from evdev import UInput, AbsInfo, ecodes
    p = plan(args)
    if args.dry_run:
        if args.json:
            json.dump({k: p[k] for k in ("target", "before", "after", "events", "device_only")},
                      sys.stdout)
            sys.stdout.write("\n")
        else:
            for e in p["events"]:
                print("%s %s %d" % (e["type"], e["code"], e["value"]))
            print("would: %s %s → %s" % (p["target"], p["before"], p["after"]))
        return 0

    etype = p["raw"][0][0]
    codes = sorted({c for _, c, _ in p["raw"]})
    if etype == ecodes.EV_ABS:
        caps = {etype: [(c, AbsInfo(value=0, min=0, max=65535, fuzz=0, flat=0, resolution=0))
                        for c in codes]}
    else:
        caps = {etype: codes}

    # The node is root:input; python-evdev would spend 1.9 s retrying to open it as the user
    # before giving up, so skip its lookup and read the sysname off our own fd instead.
    UInput._find_device = lambda self, fd: None
    ui = UInput(caps, name=VIRTUAL_NAME)
    reader = None
    observed = []
    try:
        node = node_of(ui)
        if node is None:
            sys.stderr.write("pc input inject: the virtual device produced no event node\n")
            return 1
        cmd = ["timeout", "5", "sudo", "-n", sys.executable, SELF, "_readback", node,
               "--count", str(len(p["raw"])), "--seconds", "3"]
        if args.device_only:
            cmd.append("--grab")
        reader = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
        ready = reader.stdout.readline()
        if '"ready"' not in ready:
            sys.stderr.write("pc input inject: the read-back reader did not start\n")
            return 1
        for i, (t, c, v) in enumerate(p["raw"]):
            ui.write(t, c, v)
            ui.syn()
            if args.hold_ms and i == 0 and len(p["raw"]) > 1:
                time.sleep(args.hold_ms / 1000.0)
        for _ in range(len(p["raw"])):
            line = reader.stdout.readline()
            if not line:
                break
            observed.append(tuple(json.loads(line)))
    finally:
        if reader is not None:
            try:
                reader.wait(timeout=4)
            except subprocess.TimeoutExpired:
                reader.kill()
            reader.stdout.close()
        ui.close()

    verified = observed == [tuple(e) for e in p["raw"]]
    # The input core drops a release for a key it does not hold down, so a lone KEY_* 0 —
    # the rollback of an injection — reports nothing and is verified by that silence.
    if not verified and not observed and p["raw"] == [(ecodes.EV_KEY, p["raw"][0][1], 0)]:
        verified = True
    if args.observed_file:
        with open(args.observed_file, "w") as f:
            f.write(p["after"] if verified else "unverified")
    out = {"target": p["target"], "before": p["before"], "after": p["after"],
           "device": VIRTUAL_NAME, "node": node, "device_only": args.device_only,
           "expected": p["events"], "observed": [
               {"type": ecodes.EV.get(t, str(t)), "code": name_of(t, c), "value": v}
               for t, c, v in observed],
           "verified": verified}
    if args.json:
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
    else:
        print("%s %s → %s on %s (%s), read back %d/%d event(s): %s" % (
            p["target"], p["before"], p["after"], VIRTUAL_NAME,
            "device-only, grabbed" if args.device_only else "live session",
            len(observed), len(p["raw"]), "verified" if verified else "UNVERIFIED"))
    return 0 if verified else 1


def main():
    ap = argparse.ArgumentParser(prog="pc_input.py", add_help=True)
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("devices"); d.add_argument("--json", action="store_true")
    d.set_defaults(fn=cmd_devices)
    g = sub.add_parser("grabs"); g.add_argument("--json", action="store_true")
    g.set_defaults(fn=cmd_grabs)
    c = sub.add_parser("caps"); c.add_argument("device"); c.add_argument("--json", action="store_true")
    c.set_defaults(fn=cmd_caps)
    w = sub.add_parser("watch"); w.add_argument("device")
    w.add_argument("--seconds", type=float, default=5.0); w.add_argument("--json", action="store_true")
    w.set_defaults(fn=cmd_watch)
    r = sub.add_parser("_readback"); r.add_argument("device")
    r.add_argument("--count", type=int, default=1); r.add_argument("--seconds", type=float, default=3.0)
    r.add_argument("--grab", action="store_true"); r.add_argument("--json", action="store_true")
    r.set_defaults(fn=cmd_readback)
    i = sub.add_parser("inject")
    i.add_argument("kind", choices=["key", "rel", "abs"]); i.add_argument("name")
    i.add_argument("value", nargs="?", type=int, default=None)
    i.add_argument("--hold-ms", type=int, default=0)
    i.add_argument("--device-only", action="store_true")
    i.add_argument("--dry-run", action="store_true")
    i.add_argument("--observed-file", default="")
    i.add_argument("--json", action="store_true")
    i.set_defaults(fn=cmd_inject)

    args = ap.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""AT-SPI walker behind `pc tree`, `pc a11y-click` and `pc see`: dump, find, activate or digest UI."""
import argparse, json, os, re, subprocess, sys, time
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, Gio, GLib

SKIP = {"filler", "separator", "panel"}
INT_MIN = -2147483648
DEST, WPATH, WIFACE = ("org.gnome.Shell", "/org/gnome/Shell/Extensions/Windows",
                       "org.gnome.Shell.Extensions.Windows")
KEEP = {"button", "toggle button", "checkbox", "radio button", "text", "entry", "password text",
        "combo box", "spin button", "slider", "menu item", "check menu item", "radio menu item",
        "page tab", "tab", "link", "list item", "tree item", "heading"}
BLANK_OK = {"text", "entry", "password text", "slider", "spin button", "combo box"}
TEXT_ROLES = {"text", "entry", "document text", "document web", "document frame",
              "document spreadsheet", "terminal"}
TEXT_CAP = 120


def wincall(method, args=None):
    """One call on the Window Calls D-Bus interface; None when the extension is unreachable."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        r = bus.call_sync(DEST, WPATH, WIFACE, method, args, None, Gio.DBusCallFlags.NONE, 5000, None)
    except GLib.Error:
        return None
    return r.unpack()[0] if r.n_children() else None


def windows():
    """Every window with geometry merged in, newest first as the shell reports it."""
    raw = wincall("List")
    if not raw:
        return []
    out = []
    for w in json.loads(raw):
        d = wincall("Details", GLib.Variant("(u)", (w["id"],)))
        w.update(json.loads(d) if d else {})
        out.append(w)
    return out


def screen():
    """Screen size from xrandr, or a sane default."""
    try:
        m = re.search(r"current (\d+) x (\d+)", subprocess.run(["xrandr"], capture_output=True,
                                                               text=True).stdout)
        return int(m.group(1)), int(m.group(2))
    except Exception:
        return (1366, 768)


def raw_extents(node, kind):
    """Extents of a node in one coordinate space, or None."""
    try:
        r = Atspi.Component.get_extents(node, kind)
    except Exception:
        return None
    return r


def frame_offset(frame, wins):
    """Screen origin to add to WINDOW extents, or None when SCREEN extents are already real.

    GTK4 on Wayland reports every SCREEN extent as 0,0 and Chrome reports window-relative ones;
    the frame is matched to its window (frame name == window title) and its origin reused. A frame
    larger than the window carries CSD shadows, which are half the difference on each side."""
    s, w = raw_extents(frame, Atspi.CoordType.SCREEN), raw_extents(frame, Atspi.CoordType.WINDOW)
    if s is None or w is None or s.x or s.y:
        return None
    name = frame.get_name() or ""
    win = next((x for x in wins if x.get("title") == name), None) or \
        next((x for x in wins if x.get("focus")), None)
    if win is None or "x" not in win:
        return None
    return (win["x"] - max(0, (w.width - win["width"]) // 2),
            win["y"] - max(0, (w.height - win["height"]) // 2))


def extents(node, off):
    """Screen coordinates of a node: WINDOW extents + frame origin whenever the frame reported
    a 0,0 SCREEN origin, since then the whole subtree is window-relative (GTK4 and Chrome)."""
    r = raw_extents(node, Atspi.CoordType.SCREEN)
    if r is None:
        return (0, 0, 0, 0)
    if off is not None:
        w = raw_extents(node, Atspi.CoordType.WINDOW)
        if w is not None and w.x != INT_MIN:
            return (w.x + off[0], w.y + off[1], w.width, w.height)
    if r.x == INT_MIN:
        return (0, 0, 0, 0)
    return (r.x, r.y, r.width, r.height)


def node_text(node, role):
    """First TEXT_CAP characters of a text node's content, on one line."""
    if role not in TEXT_ROLES:
        return ""
    try:
        n = Atspi.Text.get_character_count(node)
        if not n:
            return ""
        t = Atspi.Text.get_text(node, 0, min(n, TEXT_CAP))
    except Exception:
        return ""
    t = "\\n".join(x.strip() for x in t.splitlines() if x.strip()).replace('"', "'")
    return t + ("..." if n > TEXT_CAP else "")


def states(node):
    """(showing-and-visible, focused, modal) for a node."""
    try:
        s = node.get_state_set()
        return (s.contains(Atspi.StateType.SHOWING) and s.contains(Atspi.StateType.VISIBLE),
                s.contains(Atspi.StateType.FOCUSED), s.contains(Atspi.StateType.MODAL))
    except Exception:
        return (False, False, False)


TRACE = bool(os.environ.get("PC_TRACE"))
LIVE_TIMEOUT = (800, 3000)
PROBE_TIMEOUT = (60, 60)
_DESKTOP = None
DEAD = []


def desktop_apps():
    """(name, app) for every AT-SPI application that answers, cached for the process.

    A registrant that stays on the bus but stops replying (xdg-desktop-portal-gtk does) costs the
    full dbind timeout on every query, several times per run. Probe each child once under a short
    timeout, drop the ones that do not answer, and name them in DEAD so `pc see` can say so."""
    global _DESKTOP
    if _DESKTOP is not None:
        return _DESKTOP
    _DESKTOP = []
    t0 = time.perf_counter()
    try:
        d = Atspi.get_desktop(0)
        n = d.get_child_count()
    except Exception:
        return _DESKTOP
    Atspi.set_timeout(*PROBE_TIMEOUT)
    for i in range(n):
        name = ""
        try:
            a = d.get_child_at_index(i)
            if a is None:
                continue
            name = a.get_name() or ""
            if a.get_child_count() < 0:
                raise RuntimeError("no reply")
        except Exception:
            if not name:
                try:
                    pid = Atspi.Accessible.get_process_id(a)
                    name = os.path.basename(
                        open("/proc/%d/cmdline" % pid).read().split("\0")[0])
                except Exception:
                    name = "desktop child %d" % i
            DEAD.append(name)
            continue
        _DESKTOP.append((name, a))
    Atspi.set_timeout(*LIVE_TIMEOUT)
    if TRACE:
        print("trace: probe %d registrants %.3f s (dead: %s)"
              % (n, time.perf_counter() - t0, ", ".join(DEAD) or "none"), file=sys.stderr)
    return _DESKTOP


def apps(sub):
    """AT-SPI applications whose name contains sub."""
    s = sub.lower()
    return [a for name, a in desktop_apps() if not s or s in name.lower()]


def children(node):
    """(index, child) for each child the toolkit hands over; nothing when the node cannot be read."""
    try:
        n = node.get_child_count()
    except Exception:
        return
    for i in range(min(n, 200)):
        try:
            c = node.get_child_at_index(i)
        except Exception:
            continue
        if c is not None:
            yield i, c


def walk(node, depth, maxdepth, path, sink, app=0, off=None, pname=""):
    """Depth-first collection of showing nodes as dicts with screen coordinates."""
    try:
        role = node.get_role_name()
        name = node.get_name() or node_text(node, role)
    except Exception:
        return
    x, y, w, h = extents(node, off)
    show, foc, mod = states(node)
    if depth and (show or w or h):
        sink.append({"depth": depth, "role": role, "name": name, "app": app, "focused": foc,
                     "modal": mod, "x": x, "y": y, "w": w, "h": h, "path": path, "parent": pname})
    if maxdepth and depth >= maxdepth:
        return
    for i, c in children(node):
        walk(c, depth + 1, maxdepth, path + [i], sink, app, off, name)


def collect(sub, maxdepth=0, wins=None, only=None):
    """Every application matching sub, with its frames resolved to screen coordinates.

    `only` is a set of application names whose subtree is walked; the others contribute their
    application row alone. gnome-shell's tree is ~750 nodes and ~5 s of D-Bus round trips, so the
    no-app form of `pc tree` walks the focused application only (`--all` walks everything)."""
    wins = windows() if wins is None else wins
    sink = []
    for i, a in enumerate(apps(sub)):
        try:
            name = a.get_name() or ""
            sink.append({"depth": 0, "role": "application", "name": name, "app": i,
                         "focused": False, "modal": False,
                         "x": 0, "y": 0, "w": 0, "h": 0, "path": [], "parent": ""})
            if only is not None and name not in only:
                continue
            t0, n0 = time.perf_counter(), len(sink)
            for j in range(a.get_child_count()):
                f = a.get_child_at_index(j)
                if f is None:
                    continue
                walk(f, 1, maxdepth, [j], sink, i, frame_offset(f, wins), name)
            if TRACE:
                print("trace: walk %-28s %.3f s  %d nodes"
                      % (name, time.perf_counter() - t0, len(sink) - n0), file=sys.stderr)
        except Exception:
            continue
    return sink


def interactive(nodes):
    """Named controls only: drop unnamed wrappers and labels that repeat their control."""
    out, seen = [], set()
    for n in nodes:
        r, name = n["role"], n["name"]
        if r == "label":
            if not name:
                continue
        elif r not in KEEP:
            continue
        elif not name and r not in BLANK_OK:
            continue
        key = (name, n["x"], n["y"])
        if key in seen:
            continue
        seen.add(key)
        out.append(n)
    return out


def fmt(n, flat=False):
    """One tree line: role, name and screen coordinates."""
    pos = f' ({n["x"]},{n["y"]} {n["w"]}x{n["h"]})' if n["w"] or n["h"] else ""
    ind = "" if flat else "  " * n["depth"]
    if flat:
        ind = "  " if n["depth"] > 1 else ""
    return f'{"*" if n["focused"] else ""}{ind}{n["role"]} "{n["name"]}"{pos}'


def banner_labels(node, depth, sw, sh, out):
    """Collect on-screen gnome-shell labels, skipping hidden subtrees (INT_MIN extents)."""
    try:
        role = node.get_role_name()
    except Exception:
        return
    r = raw_extents(node, Atspi.CoordType.SCREEN)
    if r is None or r.x == INT_MIN:
        return
    if depth and not states(node)[0]:
        return
    if role == "label":
        name = node.get_name() or ""
        if name and r.width and 33 <= r.y < 300 and 64 <= r.x < sw and r.y + r.height <= sh:
            out.append((r.y, r.x, name))
        return
    if r.height > 0 and (r.y > 300 or r.y + r.height < 33):
        return
    if depth >= 14:
        return
    for _, c in children(node):
        banner_labels(c, depth + 1, sw, sh, out)


def notifications(limit=3):
    """Visible notification banners read from the gnome-shell a11y tree (no history API exists)."""
    sw, sh = screen()
    out = []
    for a in apps("gnome-shell"):
        banner_labels(a, 0, sw, sh, out)
        break
    out.sort()
    groups, prev = [], None
    for y, x, name in out:
        if prev is None or y - prev > 40:
            groups.append([])
        groups[-1].append(name)
        prev = y
    return [" ".join(g) for g in groups][:limit]


def clipboard():
    """First 100 characters of the clipboard on one line (wl-paste blocks when it is empty)."""
    try:
        r = subprocess.run(["timeout", "0.3", "wl-paste", "-n"], capture_output=True, text=True)
    except Exception:
        return ""
    return " ".join(r.stdout.split())[:100]


def overview_active():
    """True when the GNOME overview is up and swallowing the next click."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        r = bus.call_sync("org.gnome.Shell", "/org/gnome/Shell",
                          "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", ("org.gnome.Shell", "OverviewActive")),
                          None, Gio.DBusCallFlags.NONE, 2000, None)
        return bool(r.unpack()[0])
    except Exception:
        return False


def desktop_mode():
    """Desktop profile reported by `pc mode`: agent, human or mixed."""
    try:
        r = subprocess.run([os.path.join(os.path.dirname(os.path.realpath(__file__)), "pc-mode"),
                            "status"], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def pick_window(sel, wins):
    """The window a digest should describe: sel match, else the focused one."""
    if sel:
        s = sel.lower()
        m = [w for w in wins if s in (w.get("title") or "").lower()
             or s in (w.get("wm_class") or "").lower()]
        return m[0] if m else None
    return next((w for w in wins if w.get("focus")), None)


def app_for_window(win):
    """AT-SPI application owning a window, matched by frame name == window title."""
    if not win:
        return None
    title, cls = win.get("title") or "", win.get("wm_class") or ""
    for a in apps(""):
        try:
            for j in range(a.get_child_count()):
                f = a.get_child_at_index(j)
                if f is not None and (f.get_name() or "") == title:
                    return a.get_name() or ""
        except Exception:
            continue
    tail = cls.split(".")[-1].lower()
    for a in apps(""):
        n = (a.get_name() or "").lower()
        if tail and (tail in n.replace("-", "") or tail in n):
            return a.get_name() or ""
    return None


def slim(w):
    """Compact projection of a window row for --json."""
    return None if not w else {k: w.get(k) for k in
                               ("id", "wm_class", "title", "x", "y", "width", "height",
                                "focus", "minimized")}


DIALOG_ROLES = {"alert", "dialog", "file chooser", "color chooser"}


def find_modal(nodes):
    """The innermost showing alert/dialog node, or any node the toolkit marks MODAL."""
    hits = [n for n in nodes
            if n["depth"] and (n["role"] in DIALOG_ROLES or n["modal"]) and (n["w"] or n["h"])]
    return max(hits, key=lambda n: n["depth"]) if hits else None


def under(n, modal):
    """True when n lives inside the modal's subtree."""
    p = modal["path"]
    return n["app"] == modal["app"] and n["path"][:len(p)] == p


def modal_desc(modal, nodes):
    """One line naming a modal and the buttons that answer it."""
    btns = " | ".join(dict.fromkeys(n["name"] for n in nodes
                                    if under(n, modal) and n["role"] == "button" and n["name"]))
    return '%s "%s" (%d,%d %dx%d)%s' % (modal["role"], modal["name"], modal["x"], modal["y"],
                                        modal["w"], modal["h"], " [%s]" % btns if btns else "")


def see(sel, max_bytes, as_json):
    """Text digest of the screen: focus, windows, interactive tree, notifications, clipboard."""
    allwins = windows()
    wins = [w for w in allwins if w.get("wm_class") and w.get("title")]
    popup = next((w for w in allwins if w.get("focus") and w not in wins), None)
    win = pick_window(sel, wins)
    if win is None and not sel and wins:
        win = wins[0]
    app = app_for_window(win)
    raw = [n for n in collect(app, wins=allwins) if n["depth"]] if app else []
    modal = find_modal(raw)
    nodes = interactive([n for n in raw if under(n, modal)] if modal else raw)
    notes = notifications()
    clip = clipboard()
    ov = overview_active()
    mode = desktop_mode()

    if as_json:
        d = {"focus": slim(win), "popup": slim(popup), "windows": [slim(w) for w in wins[:15]],
             "app": app, "modal": modal_desc(modal, raw) if modal else None, "ui": nodes,
             "notifications": notes, "clip": clip, "overview": ov, "mode": mode,
             "warn": ["%s not answering AT-SPI" % n for n in DEAD]}
        out = json.dumps(d, indent=1)
        while len(out) > max_bytes and d["ui"]:
            d["ui"] = d["ui"][:-1]
            d["ui_more"] = len(nodes) - len(d["ui"])
            out = json.dumps(d, indent=1)
        return out, 0

    if win:
        head = ('focus: %s %s "%s" %dx%d+%d+%d' % (win["id"], win.get("wm_class"), win.get("title"),
                win.get("width", 0), win.get("height", 0), win.get("x", 0), win.get("y", 0)))
    elif sel:
        head = 'focus: no window matching "%s"' % sel
    else:
        head = "focus: none"
    wl = "windows: " + ("; ".join(
        '%s%s %s "%s"' % ("*" if w.get("focus") else "", w["id"], w.get("wm_class"), w.get("title"))
        for w in wins[:15]) or "none")
    if modal:
        uihead = "ui: %s %d nodes (inside the modal - the window behind it is blocked)" % (
            app, len(nodes))
        body = [fmt(n, flat=True) for n in nodes]
    elif len(nodes) < 3:
        if not win:
            uihead = "ui: none"
        elif not app:
            uihead = ("ui: no accessible application for %s (Xwayland app?) - use pc shot"
                      % win.get("wm_class"))
        else:
            uihead = "ui: %s exposes no accessible tree - use pc shot" % app
        body = []
    else:
        uihead = "ui: %s %d nodes" % (app, len(nodes))
        body = [fmt(n, flat=True) for n in nodes]
    tail = (["modal: " + modal_desc(modal, raw)] if modal else []) + (
        ["popup: %dx%d+%d+%d (GTK4 menu items are unnamed - use pc find/pc shot)" % (
            popup.get("width", 0), popup.get("height", 0), popup.get("x", 0), popup.get("y", 0))]
        if popup else []) + (["overview: active"] if ov else []) + [
        "warn: %s not answering AT-SPI" % n for n in DEAD] + [
        "notifications: " + (" | ".join(notes) if notes else "none"),
        "clip: " + clip, "mode: " + mode]

    fixed = len("\n".join([head, wl, uihead] + tail)) + 1
    budget, kept = max_bytes - fixed - 40, []
    for i, line in enumerate(body):
        if len(line) + 1 > budget:
            kept.append("... %d more (pc tree %s)" % (len(body) - i, app))
            break
        budget -= len(line) + 1
        kept.append(line)
    return "\n".join([head, wl, uihead] + kept + tail), 0


ROLE_ALIAS = {"push button": "button", "check box": "checkbox"}


def clickable(n):
    """Screen coordinates are usable once a real origin was resolved."""
    return n["w"] and n["h"] and (n["x"] or n["y"])


def matches(n, needle, role):
    if role and n["role"] != ROLE_ALIAS.get(role, role):
        return False
    name = n["name"].lower()
    return name == needle or needle in name


def focused_app(wins=None):
    """Name of the AT-SPI application owning the focused window, or ''."""
    wins = windows() if wins is None else wins
    return app_for_window(pick_window("", [w for w in wins
                                           if w.get("wm_class") and w.get("title")])) or ""


def find_nodes(sub, needle, role):
    """Named nodes matching needle, best match first.

    With no app given, the focused application is searched first: walking every application means
    walking gnome-shell's whole tree, which costs seconds."""
    for s in dict.fromkeys([sub] if sub else [focused_app(), ""]):
        hits = [n for n in collect(s) if n["name"] and matches(n, needle.lower(), role)]
        if hits:
            hits.sort(key=lambda n: (n["name"].lower() != needle.lower(), n["depth"]))
            for n in hits:
                n["sub"] = s
            return hits
    return []


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("app", nargs="?", default="")
    p.add_argument("--depth", type=int, default=0)
    p.add_argument("--json", action="store_true")
    p.add_argument("--find")
    p.add_argument("--role")
    p.add_argument("--max", type=int, default=300)
    p.add_argument("--click", action="store_true")
    p.add_argument("--interactive", action="store_true")
    p.add_argument("--see", action="store_true")
    p.add_argument("--max-bytes", type=int, default=4000)
    p.add_argument("--modal-check", action="store_true")
    p.add_argument("--all", action="store_true")
    a = p.parse_args()
    Atspi.set_timeout(*LIVE_TIMEOUT)

    if a.modal_check:
        wins = windows()
        app = app_for_window(pick_window(a.app, [w for w in wins
                                                 if w.get("wm_class") and w.get("title")]))
        raw = [n for n in collect(app, wins=wins) if n["depth"]] if app else []
        modal = find_modal(raw)
        if modal is None:
            return 1
        print(modal_desc(modal, raw))
        return 0

    if a.see:
        out, rc = see(a.app, a.max_bytes, a.json)
        print(out)
        return rc

    if a.app and not apps(a.app):
        print("pc tree: no application matching '%s' "
              "(try: pc tree | grep ^application)" % a.app, file=sys.stderr)
        return 1

    if a.find or a.click:
        hits = find_nodes(a.app, a.find or "", a.role)
        if not hits:
            print("not found", file=sys.stderr)
            return 1
        n = hits[0]
        if clickable(n):
            print(f'{n["x"] + n["w"] // 2} {n["y"] + n["h"] // 2}')
            return 0
        if not a.click:
            print("no screen coordinates; use `pc a11y-click`", file=sys.stderr)
            return 1
        try:
            node = apps(n["sub"])[n["app"]]
            for i in n["path"]:
                node = node.get_child_at_index(i)
            Atspi.Action.do_action(node, 0)
            print("action")
            return 0
        except Exception as e:
            print(f"no extents and no action: {e}", file=sys.stderr)
            return 1

    only, wins = None, None
    if not a.app and not a.all:
        wins = windows()
        f = focused_app(wins)
        only = {f} if f else set()
    nodes = collect(a.app, a.depth, wins=wins, only=only)
    if a.interactive:
        nodes = interactive([n for n in nodes if n["depth"]])
    else:
        nodes = [n for n in nodes if n["depth"] == 0 or n["role"] not in SKIP or n["name"]]
    if a.json:
        print(json.dumps(nodes[:a.max], indent=1))
        return 0
    if only is not None:
        shown = [w for w in wins if w.get("wm_class") and w.get("title")]
        print("windows: " + ("; ".join(
            '%s%s %s "%s"' % ("*" if w.get("focus") else "", w["id"], w.get("wm_class"),
                              w.get("title")) for w in shown[:15]) or "none"))
    for n in nodes[:a.max]:
        print(fmt(n, flat=a.interactive))
    if len(nodes) > a.max:
        print(f'... {len(nodes) - a.max} more nodes (raise --max)')
    if only is not None:
        rest = [n for n, _ in desktop_apps() if n not in only]
        if rest:
            print("... %d application(s) not walked: %s (pc tree <app>, or pc tree --all)"
                  % (len(rest), ", ".join(rest)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

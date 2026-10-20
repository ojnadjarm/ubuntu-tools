#!/usr/bin/env python3
"""a11y_tree.py pure functions on fake nodes; a fake gi in sys.modules makes live AT-SPI and D-Bus unreachable."""
import importlib.util, os, sys, types

BIN = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
fail = 0


def check(name, got, want):
    global fail
    good = got == want
    print(f'{"a11y-tree: " + name:64}' + ("OK" if good else f"FAIL — expected {want!r}, got {got!r}"))
    fail |= not good


class Rect:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.width, self.height = x, y, w, h


class Node:
    """Fake accessible: extents per coord kind (None raises), a name, children."""
    def __init__(self, name="", screen=None, window=None):
        self.name, self.ext = name, {0: screen, 1: window}

    def get_name(self):
        return self.name


def get_extents(node, kind):
    r = node.ext[kind]
    if r is None:
        raise RuntimeError("no Component")
    return r


def no_bus(*a, **k):
    raise RuntimeError("fake gi: no bus in tests")


Atspi = types.SimpleNamespace(CoordType=types.SimpleNamespace(SCREEN=0, WINDOW=1),
                              Component=types.SimpleNamespace(get_extents=get_extents),
                              get_desktop=no_bus, set_timeout=lambda *a: None)
Gio = types.SimpleNamespace(bus_get_sync=no_bus, BusType=types.SimpleNamespace(SESSION=0))
gi = types.ModuleType("gi")
gi.require_version = lambda *a: None
repo = types.ModuleType("gi.repository")
repo.Atspi, repo.Gio, repo.GLib = Atspi, Gio, types.SimpleNamespace(Error=Exception)
sys.modules.update({"gi": gi, "gi.repository": repo})

spec = importlib.util.spec_from_file_location("a11y_tree", os.path.join(BIN, "a11y_tree.py"))
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)

# 0. shim selftest: the module holds the fakes, and every bus or desktop entry point raises.
check("selftest: Atspi is the fake", t.Atspi is Atspi, True)
check("selftest: Gio is the fake", t.Gio is Gio, True)
check("selftest: windows() finds no bus", t.windows(), [])
check("selftest: desktop_apps() reaches no desktop", t.desktop_apps(), [])

MIN = t.INT_MIN
wins = [{"id": 1, "title": "Files", "wm_class": "org.gnome.Nautilus", "focus": False,
         "x": 300, "y": 200, "width": 800, "height": 600},
        {"id": 2, "title": "Terminal", "wm_class": "org.gnome.Ptyxis", "focus": True,
         "x": 100, "y": 50, "width": 980, "height": 680}]

# 1. frame_offset
check("frame_offset: real SCREEN origin -> None",
      t.frame_offset(Node("Files", Rect(300, 200, 800, 600), Rect(0, 0, 800, 600)), wins), None)
check("frame_offset: GTK4 0,0 matched by title",
      t.frame_offset(Node("Files", Rect(0, 0, 800, 600), Rect(0, 0, 800, 600)), wins), (300, 200))
check("frame_offset: CSD shadow halves the size difference",
      t.frame_offset(Node("Terminal", Rect(0, 0, 1000, 700), Rect(0, 0, 1000, 700)), wins), (90, 40))
check("frame_offset: unknown title falls back to the focused window",
      t.frame_offset(Node("Popup", Rect(0, 0, 980, 680), Rect(0, 0, 980, 680)), wins), (100, 50))
check("frame_offset: no geometry -> None",
      t.frame_offset(Node("X", Rect(0, 0, 9, 9), Rect(0, 0, 9, 9)), [{"title": "X"}]), None)
check("frame_offset: no extents -> None", t.frame_offset(Node("Files"), wins), None)

# 2. extents
check("extents: no offset uses SCREEN", t.extents(Node("", Rect(5, 6, 7, 8), Rect(1, 1, 7, 8)), None), (5, 6, 7, 8))
check("extents: offset adds to WINDOW", t.extents(Node("", Rect(0, 0, 7, 8), Rect(10, 20, 7, 8)), (100, 50)),
      (110, 70, 7, 8))
check("extents: WINDOW INT_MIN falls back to SCREEN",
      t.extents(Node("", Rect(5, 6, 7, 8), Rect(MIN, MIN, 0, 0)), (100, 50)), (5, 6, 7, 8))
check("extents: hidden SCREEN INT_MIN -> zeros", t.extents(Node("", Rect(MIN, MIN, 0, 0), None), None),
      (0, 0, 0, 0))
check("extents: no Component -> zeros", t.extents(Node(), (1, 1)), (0, 0, 0, 0))


def n(role, name="", depth=2, x=10, y=10, w=20, h=20, **k):
    d = {"role": role, "name": name, "depth": depth, "x": x, "y": y, "w": w, "h": h,
         "focused": False, "modal": False, "app": 0, "path": [0, 1], "parent": ""}
    d.update(k)
    return d


# 3. interactive
nodes = [n("label"), n("label", "Name"), n("filler", "box"), n("button"), n("button", "OK"),
         n("entry"), n("button", "OK"), n("button", "OK", x=50), n("heading", "Title")]
check("interactive: keeps named controls, blank entries, dedups name+position",
      [(x["role"], x["name"], x["x"]) for x in t.interactive(nodes)],
      [("label", "Name", 10), ("button", "OK", 10), ("entry", "", 10), ("button", "OK", 50),
       ("heading", "Title", 10)])

# 4. find_modal, under, modal_desc
check("find_modal: none", t.find_modal([n("button", "OK")]), None)
outer, inner = n("dialog", "Save", depth=2, path=[0]), n("alert", "Overwrite?", depth=4, path=[0, 1, 2])
check("find_modal: innermost dialog wins", t.find_modal([outer, inner, n("button", "OK")]), inner)
flag = n("panel", "sheet", depth=3, modal=True)
check("find_modal: MODAL state counts", t.find_modal([flag]), flag)
check("find_modal: zero-size and depth-0 dialogs ignored",
      t.find_modal([n("dialog", "gone", w=0, h=0), n("dialog", "app", depth=0)]), None)
btns = [n("button", "Replace", path=[0, 1, 2, 0]), n("button", "Cancel", path=[0, 1, 2, 1]),
        n("button", "Replace", path=[0, 1, 2, 3]), n("button", "Behind", path=[1, 0])]
check("under: inside vs outside the modal path", [t.under(b, inner) for b in btns], [True, True, True, False])
check("modal_desc: role, name, geometry, unique buttons", t.modal_desc(inner, btns),
      'alert "Overwrite?" (10,10 20x20) [Replace | Cancel]')

# 5. pick_window
check("pick_window: title substring, any case", t.pick_window("fIL", wins)["id"], 1)
check("pick_window: wm_class substring", t.pick_window("ptyxis", wins)["id"], 2)
check("pick_window: no match -> None", t.pick_window("firefox", wins), None)
check("pick_window: empty sel -> focused", t.pick_window("", wins)["id"], 2)
check("pick_window: nothing focused -> None", t.pick_window("", wins[:1]), None)

# 6. matches, clickable
check("matches: substring of a lowered needle", t.matches(n("button", "Save As"), "save", None), True)
check("matches: role alias push button", t.matches(n("button", "Save"), "save", "push button"), True)
check("matches: role alias check box", t.matches(n("checkbox", "Wrap"), "wrap", "check box"), True)
check("matches: role mismatch", t.matches(n("link", "Save"), "save", "button"), False)
check("matches: name miss", t.matches(n("button", "Open"), "save", None), False)
check("clickable: sized with an origin", bool(t.clickable(n("button", x=0, y=5))), True)
check("clickable: zero size", bool(t.clickable(n("button", w=0))), False)
check("clickable: unresolved 0,0 origin", bool(t.clickable(n("button", x=0, y=0))), False)

# 7. fmt
check("fmt: tree indent by depth", t.fmt(n("button", "OK", depth=2)), '    button "OK" (10,10 20x20)')
check("fmt: focused star, no geometry when zero", t.fmt(n("entry", "", depth=1, w=0, h=0, focused=True)),
      '*  entry ""')
check("fmt: flat depth 1 has no indent", t.fmt(n("button", "OK", depth=1), flat=True), 'button "OK" (10,10 20x20)')
check("fmt: flat depth >1 indents once", t.fmt(n("button", "OK", depth=5), flat=True),
      '  button "OK" (10,10 20x20)')

sys.exit(fail)

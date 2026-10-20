#!/usr/bin/env python3
"""pc-wait-for on a fake a11y_tree: -h and bad flags never import gi; match()/holds()/main() rc on fake windows."""
import contextlib, importlib.machinery, importlib.util, io, os, subprocess, sys, types

BIN = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
fail = 0


def check(name, got, want):
    global fail
    good = got == want
    print(f'{"pc-wait-for: " + name:64}' + ("OK" if good else f"FAIL — expected {want!r}, got {got!r}"))
    fail |= not good


loader = importlib.machinery.SourceFileLoader("pc_wait_for", os.path.join(BIN, "pc-wait-for"))
spec = importlib.util.spec_from_loader("pc_wait_for", loader)
w = importlib.util.module_from_spec(spec)
loader.exec_module(w)


def run(*argv):
    """main() with argv; returns (rc, stdout); argparse exits become their code."""
    sys.argv, out = ["pc-wait-for", *argv], io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        try:
            rc = w.main()
        except SystemExit as e:
            rc = e.code
    return rc, out.getvalue()


# 1. no live import before the condition is known
check("load: a11y_tree not imported", "a11y_tree" in sys.modules, False)
check("-h: rc 0 and usage", (run("-h")[0], run("-h")[1].startswith("usage:")), (0, True))
check("bad flag: rc 2", run("--nope")[0], 2)
check("no condition: rc 2", run()[0], 2)
check("two conditions: rc 2", run("--window", "a", "--gone", "b")[0], 2)
check("-h/bad flag: gi never imported", "gi" in sys.modules, False)
check("-h/bad flag: a11y_tree never imported", "a11y_tree" in sys.modules, False)
check("-h: text is USAGE byte for byte", run("-h"), (0, w.USAGE + "\n"))
check("--help: text is USAGE byte for byte", run("--help"), (0, w.USAGE + "\n"))
r = subprocess.run([sys.executable, "-X", "importtime", os.path.join(BIN, "pc-wait-for"), "-h"],
                   capture_output=True, text=True)
check("-h as a process: rc 0, USAGE, argparse never imported",
      (r.returncode, r.stdout, "argparse" in r.stderr), (0, w.USAGE + "\n", False))

# 2. fake a11y_tree: windows and nodes are plain data, no bus
WINS = [{"title": "Files", "wm_class": "org.gnome.Nautilus", "focus": False},
        {"title": "Terminal", "wm_class": "org.gnome.Ptyxis", "focus": True}]
NODES = [{"name": "root", "depth": 0}, {"name": "Save As", "depth": 1}, {"name": "Cancel", "depth": 2}]
fake = types.ModuleType("a11y_tree")
fake.windows = lambda: WINS
fake.app_for_window = lambda win: "app:" + win["title"] if win else None
fake.collect = lambda app: NODES if app else []
fake.interactive = lambda nodes: nodes
fake.Atspi = types.SimpleNamespace(set_timeout=lambda *a: None)
fake.see = lambda *a: ("seen", None)
sys.modules["a11y_tree"] = fake

check("selftest: main binds the fake", (run("--window", "files")[0], w.A is fake), (0, True))

# 3. match
check("match: title, any case", [x["title"] for x in w.match(WINS, "FILES")], ["Files"])
check("match: wm_class", [x["title"] for x in w.match(WINS, "ptyxis")], ["Terminal"])
check("match: none", w.match(WINS, "firefox"), [])


def args(**kw):
    base = dict(window=None, focus=None, text=None, gone=None, app="")
    return types.SimpleNamespace(**{**base, **kw})


# 4. holds
check("holds: window present", w.holds(args(window="nautilus")), True)
check("holds: window absent", w.holds(args(window="firefox")), False)
check("holds: focus on focused window", w.holds(args(focus="terminal")), True)
check("holds: focus on unfocused window", w.holds(args(focus="files")), False)
check("holds: gone when absent", w.holds(args(gone="firefox")), True)
check("holds: gone when present", w.holds(args(gone="files")), False)
check("holds: text exact, any case", w.holds(args(text="cancel")), True)
check("holds: text substring", w.holds(args(text="save")), True)
check("holds: text skips depth-0 root", w.holds(args(text="root")), False)
check("holds: text missing", w.holds(args(text="Open")), False)
WINS[1]["focus"] = False
check("holds: text, no focused window and no --app", w.holds(args(text="cancel")), False)
check("holds: text with --app", w.holds(args(text="cancel", app="x")), True)
WINS[1]["focus"] = True

# 5. main rc
rc, out = run("--focus", "terminal", "--see")
check("main: ok rc 0 and --see output", (rc, out.startswith("ok after"), "seen" in out), (0, True, True))
rc, out = run("--window", "firefox", "--timeout", "0")
check("main: timeout rc 1", (rc, out.startswith("timeout after")), (1, True))
check("selftest: gi still never imported", "gi" in sys.modules, False)

sys.exit(1 if fail else 0)

#!/usr/bin/env python3
"""make-fixture.py --seed <n> <dir> --key <file> [--modules 24 --bugs 8]: a seeded Python package with planted bugs.

Writes <dir>/ledgerkit (modules), <dir>/tests (a noisy unittest suite), TASK.md and QUESTIONS.md; the answer key, the
known patch and the tests' hash go to --key (JSON), outside the fixture. Same seed, same bytes.
"""
import argparse, difflib, hashlib, json, os, random, sys

PKG = "ledgerkit"
WORDS = ["tariff", "ledger", "invoice", "route", "batch", "quota", "parcel", "meter", "voucher", "tally", "credit",
         "freight", "levy", "rebate", "stock", "permit", "ration", "token", "bundle", "ticket", "harbor", "depot",
         "relay", "cargo", "clerk", "audit", "pallet", "escrow", "ferry", "bond", "manifest", "docket", "convoy",
         "tithe", "crate", "toll", "bushel", "parity", "census", "mint"]
TINTS = ["amber", "cobalt", "saffron", "umber", "ochre", "teal", "crimson", "slate", "ivory", "jade", "onyx", "coral",
         "sienna", "indigo"]
VERBS = ["Fold", "Weigh", "Settle", "Sweep", "Balance", "Rank", "Trim", "Spread", "Merge", "Score"]


def filler(rng, mod, n, consts):
    """One self-contained function of 11 to 19 lines over the module's constants; returns (name, src, args)."""
    name = "%s_%s_%d" % (rng.choice(VERBS).lower(), mod, n)
    c = rng.choice(consts)
    m, k, d, mod_ = rng.randint(2, 7), rng.randint(2, 9), rng.randint(1, 40), rng.randint(50, 997)
    kind = rng.randrange(3)
    doc = '    """%s the values by the %s rule %d."""\n' % (rng.choice(VERBS), mod, n)
    if kind == 0:
        src = ("def %s(values, scale=%d):\n" % (name, k) + doc +
               "    total = 0\n    for i, v in enumerate(values):\n"
               "        if v %% %d == 0:\n            total += v * scale\n"
               "        elif i %% 2:\n            total -= v + %d\n        else:\n            total += %s\n"
               "    if total < 0:\n        total = -total %% %d\n    return total + %d\n" % (m, d, c, mod_, d))
    elif kind == 1:
        src = ("def %s(values, limit=%d):\n" % (name, mod_) + doc +
               "    seen = []\n    for v in values:\n        w = (v * %d + %s) %% limit\n"
               "        if w in seen:\n            w = (w + %d) %% limit\n        seen.append(w)\n"
               "    best = max(seen) if seen else 0\n    worst = min(seen) if seen else 0\n"
               "    spread = best - worst\n    return spread * %d + len(seen)\n" % (k, c, d, m))
    else:
        src = ("def %s(values, base=%d):\n" % (name, d) + doc +
               "    acc = base\n    run = 0\n    for v in values:\n        run = run + 1 if v > acc %% %d else 0\n"
               "        acc = (acc * %d + v + %s) %% %d\n        if run > %d:\n            acc //= 2\n"
               "            run = 0\n    return acc\n" % (m * 10, k, c, mod_, m))
    return name, src, [rng.randint(1, 99) for _ in range(rng.randint(4, 9))]


def build(seed, n_mod, n_bug):
    rng = random.Random(seed)
    mods = rng.sample(WORDS, n_mod)
    pos = rng.sample(range(n_mod), 2 * n_bug)
    pairs = sorted(zip(pos[::2], pos[1::2]))          # (consumer, provider), sorted by the consumer's test file
    tints = rng.sample(TINTS, n_bug)
    role = {}
    bugs = []
    for i, (ci, pi) in enumerate(pairs):
        kind = ("const", "order", "key")[i % 3]
        X = tints[i].upper()
        lo, hi = rng.choice([("LOW", "HIGH"), ("RATE", "RATIO"), ("FLOOR", "FACTOR"), ("BASE", "BAND")])
        if rng.random() < 0.5:
            lo, hi = hi, lo
        b = dict(n=i + 1, kind=kind, consumer=mods[ci], provider=mods[pi], X=X, wrongc=X + "_" + lo,
                 rightc=X + "_" + hi, v1=rng.randint(3, 19), v2=rng.randint(21, 49), k=rng.randint(3, 13),
                 wrong_first=rng.random() < 0.5, mod_import=rng.random() < 0.5)
        b["bfun"] = "%s_%s" % (rng.choice(VERBS).lower(), tints[i])
        b["afun"] = "%s_%s_%d" % (rng.choice(VERBS).lower(), mods[ci], rng.randint(20, 60))
        role[ci], role[pi] = ("c", b), ("p", b)
        bugs.append(b)
    files, fixed, tests = {}, {}, {}
    for i, mod in enumerate(mods):
        consts = ["%s_%s" % (mod.upper(), s) for s in ("BASE", "SPAN", "SEED", "MARGIN")]
        head = ['"""%s: %s helpers for the ledger kit."""' % (mod, mod)]
        r, b = role.get(i, (None, None))
        q = ""
        if r == "c":
            names = {"const": "%s, %s" % (b["wrongc"], b["rightc"]), "order": b["bfun"], "key": b["X"] + "_TABLE"}
            if b["mod_import"]:
                head.append("from . import %s" % b["provider"])
                q = b["provider"] + "."
            else:
                head.append("from .%s import %s" % (b["provider"], names[b["kind"]]))
        head.append("")
        head += ["%s = %d" % (c, rng.randint(2, 60)) for c in consts]
        bug_src = fix_src = ""
        if r == "p" and b["kind"] == "const":
            head += ["%s = %d" % (b["wrongc"], b["v1"]), "%s = %d" % (b["rightc"], b["v2"])]
            bug_src = fix_src = ('def %s(n):\n    """Return n bounded by the limit."""\n    return min(n, %s)\n'
                                 % (b["bfun"], b["wrongc"]))
        elif r == "p" and b["kind"] == "order":
            head.append("%s_STEP = %d" % (b["X"], b["k"]))
            bug_src = fix_src = ('def %s(base, step):\n    """Advance base by step units."""\n'
                                 '    return base + step * %s_STEP\n' % (b["bfun"], b["X"]))
        elif r == "p":
            head.append('%s_TABLE = {"net": %d, "gross": %d, "tare": %d}' % (b["X"], b["v1"], b["v2"], b["k"]))
            bug_src = fix_src = ('def %s(kind="net"):\n    """Return the table rate for kind."""\n'
                                 '    return %s_TABLE[kind]\n' % (b["bfun"], b["X"]))
        elif r == "c" and b["kind"] == "const":
            t = 'def %s(qty):\n    """Charge qty units at the agreed rate."""\n    return qty * %s%s\n'
            bug_src, fix_src = t % (b["afun"], q, b["wrongc"]), t % (b["afun"], q, b["rightc"])
        elif r == "c" and b["kind"] == "order":
            t = 'def %s(start, count):\n    """Schedule count slots from start."""\n    return %s%s(%s)\n'
            bug_src = t % (b["afun"], q, b["bfun"], "count, start")
            fix_src = t % (b["afun"], q, b["bfun"], "start, count")
        elif r == "c":
            t = 'def %s(qty):\n    """Price qty units at the table rate."""\n    return qty * %s%s_TABLE["%s"]\n'
            bug_src, fix_src = t % (b["afun"], q, b["X"], "net"), t % (b["afun"], q, b["X"], "gross")
        target = rng.randint(130, 190)
        blocks, fills, j, size = [], [], 0, len(head) + (bug_src.count("\n") + 1 if bug_src else 0)
        while True:
            name, src, args = filler(rng, mod, j, consts)
            if size + src.count("\n") + 1 > target:
                break
            blocks.append(src.rstrip("\n"))
            fills.append((name, src, args))
            size += src.count("\n") + 1
            j += 1
        head += ["%s_RESERVE_%d = %d" % (mod.upper(), n, rng.randint(1, 99)) for n in range(max(0, target - size))]
        at = rng.randint(0, len(blocks))
        def text(extra):
            bl = blocks[:at] + ([extra.rstrip("\n")] if extra else []) + blocks[at:]
            return "\n".join(head) + "\n" + "".join("\n" + x + "\n" for x in bl)
        files[mod], fixed[mod] = text(bug_src), text(fix_src)
        ns = {}
        exec("\n".join(l for l in head if " import " not in l and not l.startswith('"""')) + "\n" +
             "\n".join(s for _, s, _ in fills), ns)
        tests[mod] = [(n_, a, ns[n_](a)) for n_, _, a in fills]
    return mods, bugs, files, fixed, tests


def test_files(mods, bugs, tests, n_tests):
    """One test file per module: bug tests, guard tests, then filler tests round robin up to n_tests."""
    cases = {m: [] for m in mods}
    for b in bugs:
        if b["kind"] in ("const", "key"):
            cases[b["consumer"]].append("self.assertEqual(%s.%s(5), %d)" % (b["consumer"], b["afun"], 5 * b["v2"]))
            arg = "1000" if b["kind"] == "const" else ""
            cases[b["provider"]].append("self.assertEqual(%s.%s(%s), %d)" % (b["provider"], b["bfun"], arg, b["v1"]))
        else:
            cases[b["consumer"]].append("self.assertEqual(%s.%s(100, 3), %d)" % (b["consumer"], b["afun"], 100 + 3 * b["k"]))
            cases[b["provider"]].append("self.assertEqual(%s.%s(10, 2), %d)" % (b["provider"], b["bfun"], 10 + 2 * b["k"]))
    left = n_tests - 2 * len(bugs)
    idx = {m: 0 for m in mods}
    while left > 0:
        for m in mods:
            if left and idx[m] < len(tests[m]):
                n_, a, v = tests[m][idx[m]]
                cases[m].append("self.assertEqual(%s.%s(%r), %r)" % (m, n_, a, v))
                idx[m] += 1
                left -= 1
    out = {}
    for i, m in enumerate(mods):
        lines = ["import unittest", "", "from %s import %s" % (PKG, m), "from _trace import trace", "", "",
                 "class %sTest(unittest.TestCase):" % m.capitalize()]
        for j, c in enumerate(cases[m]):
            lines += ["    def test_%s_%d(self):" % (m, j), "        trace(self.id())", "        " + c, ""]
        out["test_%02d_%s.py" % (i, m)] = "\n".join(lines) + "\n"
    return out


TRACE = '''"""Debug trace every test prints (noise the suite always shows)."""
import hashlib


def trace(name):
    h = hashlib.sha256(name.encode()).hexdigest()
    print("[trace] %s ctx=%s state=%s spans=%s lease=%s" % (name.rsplit(".", 1)[-1], h[:24], h[24:56] * 2, h[8:56],
                                                            h[40:64]))
'''


def questions(bugs):
    """Six one-word questions met while fixing bugs 1 to 3; returns (markdown, answers)."""
    b1, b2, b3 = bugs[:3]
    def value(b):
        n = {"const": b["rightc"], "order": b["X"] + "_STEP", "key": '%s_TABLE["gross"]' % b["X"]}[b["kind"]]
        return "What is the value of `%s`?" % n, str(b["k"] if b["kind"] == "order" else b["v2"])
    def module(b):
        n = {"const": b["rightc"], "order": b["bfun"], "key": b["X"] + "_TABLE"}[b["kind"]]
        return "Which module of `%s` defines `%s`, used by `%s`? (module name, no `.py`)" % (PKG, n, b["afun"]), b["provider"]
    def which(b):
        if b["kind"] == "const":
            wrong = "set `%s` to the value of `%s`" % (b["wrongc"], b["rightc"])
            right = "make `%s` use `%s`" % (b["afun"], b["rightc"])
        elif b["kind"] == "key":
            wrong = 'set `%s_TABLE["net"]` to the value of `%s_TABLE["gross"]`' % (b["X"], b["X"])
            right = 'make `%s` read `%s_TABLE["gross"]`' % (b["afun"], b["X"])
        else:
            wrong = "swap the roles of `base` and `step` inside `%s`" % b["bfun"]
            right = "swap the two arguments `%s` passes to `%s`" % (b["afun"], b["bfun"])
        a, z = (wrong, right) if b["wrong_first"] else (right, wrong)
        return ("Both fixes make the failing test of `%s` pass. First: %s. Second: %s. Which one makes another test "
                "fail? (`first` or `second`)" % (b["afun"], a, z)), "first" if b["wrong_first"] else "second"
    qa = [value(b1), which(b1), module(b2), value(b2), module(b3), which(b3)]
    md = "# Questions\n\nAnswer each in one word in `ANSWERS.json`: `{\"Q1\": \"...\", ..., \"Q6\": \"...\"}`.\n\n"
    md += "".join("%d. %s\n" % (i + 1, q) for i, (q, _) in enumerate(qa))
    return md, {"Q%d" % (i + 1): a for i, (_, a) in enumerate(qa)}


TASK = """# Task

The package `ledgerkit` fails its unittest suite. Make it green; do not edit anything under `tests/`:

    python3 -m unittest discover -s tests

Then answer every question in `QUESTIONS.md` in `ANSWERS.json` (one word each).
"""


def tree_hash(d):
    h = hashlib.sha256()
    for f in sorted(os.listdir(d)):
        if f.endswith(".py"):
            h.update(f.encode() + b"\0" + open(os.path.join(d, f), "rb").read())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dir")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--modules", type=int, default=24)
    ap.add_argument("--bugs", type=int, default=8)
    a = ap.parse_args()
    key = os.path.realpath(a.key)
    if key.startswith(os.path.realpath(a.dir) + os.sep):
        sys.exit("make-fixture: --key must be outside the fixture")
    mods, bugs, files, fixed, tests = build(a.seed, a.modules, a.bugs)
    os.makedirs(os.path.join(a.dir, PKG))
    os.makedirs(os.path.join(a.dir, "tests"))
    w = lambda p, s: open(os.path.join(a.dir, p), "w").write(s)
    w(os.path.join(PKG, "__init__.py"), '"""ledgerkit: small ledger helpers."""\n')
    for m in mods:
        w(os.path.join(PKG, m + ".py"), files[m])
    for f, s in test_files(mods, bugs, tests, round(60 * a.modules / 24)).items():
        w(os.path.join("tests", f), s)
    w(os.path.join("tests", "_trace.py"), TRACE)
    w("TASK.md", TASK)
    md, answers = questions(bugs)
    w("QUESTIONS.md", md)
    patch = "".join("".join(difflib.unified_diff(files[m].splitlines(True), fixed[m].splitlines(True),
                                                 "a/%s/%s.py" % (PKG, m), "b/%s/%s.py" % (PKG, m)))
                    for m in mods if files[m] != fixed[m])
    json.dump({"seed": a.seed, "modules": a.modules, "bugs": [{k: b[k] for k in ("n", "kind", "consumer", "provider")}
                                                              for b in bugs],
               "answers": answers, "tests_sha256": tree_hash(os.path.join(a.dir, "tests")), "patch": patch},
              open(key, "w"), indent=1)


if __name__ == "__main__":
    main()

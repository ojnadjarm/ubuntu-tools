#!/usr/bin/env python3
"""make-fixture.py --seed <n> <dir> --key <file> [--modules 24 --bugs 8]: a seeded Python package with planted bugs.

Writes <dir>/ledgerkit (modules), <dir>/tests (a noisy unittest suite), TASK.md and QUESTIONS.md; the answer key, the
known patch and the tests' hash go to --key (JSON), outside the fixture. Same seed, same bytes.
"""
import argparse, base64, difflib, hashlib, json, os, random, re, sys

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


def new_bug(rng, n, kind, consumer, provider, tint):
    """One planted bug: a consumer module misusing a name its provider module defines."""
    X = tint.upper()
    lo, hi = rng.choice([("LOW", "HIGH"), ("RATE", "RATIO"), ("FLOOR", "FACTOR"), ("BASE", "BAND")])
    if rng.random() < 0.5:
        lo, hi = hi, lo
    b = dict(n=n, kind=kind, consumer=consumer, provider=provider, X=X, wrongc=X + "_" + lo,
             rightc=X + "_" + hi, v1=rng.randint(3, 19), v2=rng.randint(21, 49), k=rng.randint(3, 13),
             wrong_first=rng.random() < 0.5, mod_import=rng.random() < 0.5)
    b["bfun"] = "%s_%s" % (rng.choice(VERBS).lower(), tint)
    b["afun"] = "%s_%s_%d" % (rng.choice(VERBS).lower(), consumer, rng.randint(20, 60))
    return b


def module(rng, mod, r, b):
    """One module of 130 to 190 lines in role r (None, "c", "p", "carry"); returns (text, fixed text, filler tests)."""
    consts = ["%s_%s" % (mod.upper(), s) for s in ("BASE", "SPAN", "SEED", "MARGIN")]
    head = ['"""%s: %s helpers for the ledger kit."""' % (mod, mod)]
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
    if r == "carry":
        head.append("%s_CARRY = 0" % mod.upper())
        bug_src = fix_src = ('def carry_%s(qty):\n    """Charge qty units at the carried rate."""\n'
                             '    return qty * %s_CARRY\n' % (mod, mod.upper()))
    elif r == "p" and b["kind"] == "const":
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
    fixed = text(fix_src)
    if r == "carry":
        fixed = fixed.replace("%s_CARRY = 0\n" % mod.upper(), "%s_CARRY = %d\n" % (mod.upper(), b["v2"]))
    ns = {}
    exec("\n".join(l for l in head if " import " not in l and not l.startswith('"""')) + "\n" +
         "\n".join(s for _, s, _ in fills), ns)
    return text(bug_src), fixed, [(n_, a, ns[n_](a)) for n_, _, a in fills]


def build(seed, n_mod, n_bug):
    rng = random.Random(seed)
    mods = rng.sample(WORDS, n_mod)
    pos = rng.sample(range(n_mod), 2 * n_bug)
    pairs = sorted(zip(pos[::2], pos[1::2]))          # (consumer, provider), sorted by the consumer's test file
    tints = rng.sample(TINTS, n_bug)
    role = {}
    bugs = []
    for i, (ci, pi) in enumerate(pairs):
        b = new_bug(rng, i + 1, ("const", "order", "key")[i % 3], mods[ci], mods[pi], tints[i])
        role[ci], role[pi] = ("c", b), ("p", b)
        bugs.append(b)
    files, fixed, tests = {}, {}, {}
    for i, mod in enumerate(mods):
        r, b = role.get(i, (None, None))
        files[mod], fixed[mod], tests[mod] = module(rng, mod, r, b)
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


def which(b):
    """Which of two passing fixes breaks another test: the fix in the provider."""
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


def questions(bugs):
    """Six one-word questions met while fixing bugs 1 to 3; returns (markdown, answers)."""
    b1, b2, b3 = bugs[:3]
    def value(b):
        n = {"const": b["rightc"], "order": b["X"] + "_STEP", "key": '%s_TABLE["gross"]' % b["X"]}[b["kind"]]
        return "What is the value of `%s`?" % n, str(b["k"] if b["kind"] == "order" else b["v2"])
    def module(b):
        n = {"const": b["rightc"], "order": b["bfun"], "key": b["X"] + "_TABLE"}[b["kind"]]
        return "Which module of `%s` defines `%s`, used by `%s`? (module name, no `.py`)" % (PKG, n, b["afun"]), b["provider"]
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


STAGE_MODS = 3
STAGE_TESTS = 8
STAGE_WORDS = WORDS + ["wharf", "quay", "sluice", "lantern", "anvil", "bellows", "furnace", "kiln", "loom", "spindle",
                       "mill", "granary", "silo", "barrel", "cask", "keg", "flask", "ingot", "bullion", "gauge", "dial",
                       "lever", "pulley", "winch", "crane", "hoist", "barge", "skiff", "sloop", "galley", "tender",
                       "courier", "herald", "notary", "scribe", "steward", "warden", "bailiff", "reeve", "purser",
                       "broker", "dealer", "vendor", "hawker", "peddler", "merchant", "trader", "banker", "lender",
                       "debtor", "pawn", "lien", "deed", "charter", "almanac", "abacus"]
STAGE_TINTS = TINTS + ["russet", "mauve", "olive", "azure", "cerise", "khaki", "lilac", "maroon", "navy", "pewter",
                       "plum", "rust", "sable", "scarlet", "sepia", "taupe", "topaz", "violet", "beryl", "copper",
                       "bronze", "garnet"]

TASK_STAGED = """# Task

The package `ledgerkit` comes in %d stages; only stage 1 is here now. Each stage brings new modules, their tests and
a work order `stage-<n>.md`. Run `python3 gate.py`: it runs the unittest suite of the open stages and, once the suite
is green, opens the next stage. Do every stage's work order and make the suite green; do not edit anything under
`tests/`, `gate.py` or `stages.bin`. When the last stage is green the gate writes `QUESTIONS.md`: answer every question
in `ANSWERS.json` (one word each).
"""

GATE = r'''#!/usr/bin/env python3
"""gate.py: run the suite of the open stages; once it is green, open the next stage."""
import base64, hashlib, importlib, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROBES = None


def xor(key, data):
    out = bytearray()
    for i in range(0, len(data), 32):
        out += bytes(x ^ y for x, y in zip(data[i:i + 32], hashlib.sha256(key + i.to_bytes(8, "big")).digest()))
    return bytes(out)


def key_of(outs):
    return hashlib.sha256(json.dumps(outs).encode()).digest()


def main():
    last = len(PROBES)
    n = max(k for k in range(1, last + 1) if os.path.exists(os.path.join(HERE, "stage-%d.md" % k)))
    if subprocess.call([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests"], cwd=HERE):
        sys.exit("gate: stage %d is red" % n)
    if n == last and os.path.exists(os.path.join(HERE, "QUESTIONS.md")):
        sys.exit(print("gate: all %d stages are green; QUESTIONS.md is open" % last))
    sys.dont_write_bytecode = True
    sys.path.insert(0, HERE)
    k = key_of([getattr(importlib.import_module("ledgerkit." + m), f)(*a) for m, f, a in PROBES[n - 1]])
    blob = json.load(open(os.path.join(HERE, "stages.bin")))[n - 1]
    pt = xor(k, base64.b64decode(blob["ct"]))
    if hashlib.sha256(k + pt).hexdigest()[:16] != blob["mac"]:
        sys.exit("gate: the suite is green but stage %d does not compute what it should" % n)
    files = json.loads(pt)
    for p, s in files.items():
        os.makedirs(os.path.dirname(os.path.join(HERE, p)), exist_ok=True)
        open(os.path.join(HERE, p), "w").write(s)
    print("gate: stage %d is green; opened %s" % (n, " ".join(sorted(files))))
    for p in sorted(files):
        if p.endswith(".md"):
            print("\n" + files[p])


if __name__ == "__main__":
    main()
'''

SEAL = '''

def seal(x):
    return hashlib.sha256(("ledgerkit:%r" % (x,)).encode()).hexdigest()[:16]
'''


def bug_calls(b):
    """The bug's test calls as (module, function, args, expected): the consumer's, then the provider's if it is new."""
    if b["kind"] == "order":
        c = [(b["consumer"], b["afun"], [100, 3], 100 + 3 * b["k"])]
        p = [(b["provider"], b["bfun"], [10, 2], 10 + 2 * b["k"])]
    else:
        c = [(b["consumer"], b["afun"], [5], 5 * b["v2"])]
        p = [(b["provider"], b["bfun"], [1000] if b["kind"] == "const" else [], b["v1"])]
    return c + ([] if b.get("reuse") else p)


def build_staged(seed, stages):
    """stages x 3 modules: bug A in a new consumer and provider, and a third module: plain up to stage 3, then on even
    stages a carry module that needs stage s-3's rate, on odd ones a consumer of stage s-3's provider (same dead end)."""
    rng = random.Random(seed)
    mods = rng.sample(STAGE_WORDS, stages * STAGE_MODS)
    tints = rng.sample(STAGE_TINTS, stages)
    bugs, plan, files, fixed, tests = [], [], {}, {}, {}
    for s in range(1, stages + 1):
        pool = mods[(s - 1) * STAGE_MODS:s * STAGE_MODS]
        kind = ("const", "order", "key", "const")[(s - 1) % 4]       # odd stages const or key: the carried rates
        a = new_bug(rng, len(bugs) + 1, kind, pool[0], pool[1], tints[s - 1])
        a.update(stage=s, slot="A")
        role, found, carry = {pool[0]: ("c", a), pool[1]: ("p", a)}, [a], None
        if s >= 4:
            e = [x for x in bugs if x["stage"] == s - 3 and x["slot"] == "A"][0]
            if s % 2 == 0:
                carry = e
                role[pool[2]] = ("carry", e)
            else:
                b = dict(e, n=len(bugs) + 2, consumer=pool[2], reuse=True, mod_import=rng.random() < 0.5,
                         afun="%s_%s_%d" % (rng.choice(VERBS).lower(), pool[2], rng.randint(20, 60)), stage=s, slot="B")
                role[pool[2]] = ("c", b)
                found.append(b)
        bugs += found
        for m in pool:
            files[m], fixed[m], tests[m] = module(rng, m, *role.get(m, (None, None)))
        plan.append(dict(stage=s, mods=pool, bugs=found, carry=pool[2] if carry else None, early=carry))
    return plan, bugs, files, fixed, tests


def staged_parts(plan, files, tests, stages):
    """Per stage: its files (modules, tests, work order), its probes; the tests' tree hash over all stages."""
    ns = {}
    exec(SEAL.replace("\n\n", "import hashlib\n", 1), ns)
    parts, probes, alltests, i = [], [], {"_trace.py": TRACE + SEAL}, 0
    for st in plan:
        calls = [c for b in st["bugs"] for c in bug_calls(b)]
        if st["carry"]:
            calls.append((st["carry"], "carry_" + st["carry"], [7], 7 * st["early"]["v2"]))
        probes.append(calls)
        cases = {m: [] for m in st["mods"]}
        for m, f, args, v in calls:
            got = "%s.%s(%s)" % (m, f, ", ".join(map(str, args)))
            cases[m].append('self.assertEqual(seal(%s), "%s")' % (got, ns["seal"](v)) if f.startswith("carry_")
                            else "self.assertEqual(%s, %d)" % (got, v))
        left, idx = STAGE_TESTS - len(calls), {m: 0 for m in st["mods"]}
        while left > 0:
            for m in st["mods"]:
                if left and idx[m] < len(tests[m]):
                    n_, a, v = tests[m][idx[m]]
                    cases[m].append("self.assertEqual(%s.%s(%r), %r)" % (m, n_, a, v))
                    idx[m] += 1
                    left -= 1
        out = {}
        for m in st["mods"]:
            lines = ["import unittest", "", "from %s import %s" % (PKG, m), "from _trace import seal, trace", "", "",
                     "class %sTest(unittest.TestCase):" % m.capitalize()]
            for j, c in enumerate(cases[m]):
                lines += ["    def test_%s_%d(self):" % (m, j), "        trace(self.id())", "        " + c, ""]
            out["test_%02d_%s.py" % (i, m)] = "\n".join(lines) + "\n"
            i += 1
        alltests.update(out)
        order = ("# Stage %d of %d\n\nNew in this stage: %s and their tests. Their tests are red: find the causes and "
                 "fix them.\n") % (
            st["stage"], stages, ", ".join("`%s/%s.py`" % (PKG, m) for m in st["mods"]))
        if st["carry"]:
            order += ("\n`%s.carry_%s` charges at a rate that is still unset (`%s_CARRY = 0` in `%s/%s.py`): it must "
                      "charge the same rate per unit as the charge you fixed in `%s/%s.py` in stage %d.\n"
                      % (st["carry"], st["carry"], st["carry"].upper(), PKG, st["carry"], PKG,
                         st["early"]["consumer"], st["early"]["stage"]))
        order += "\nWhen the suite is green, run `python3 gate.py` to open the next stage.\n\n## Index of the new modules\n"
        for m in st["mods"]:
            order += "\n`%s/%s.py`:\n" % (PKG, m) + "".join(
                "- `%s`: %s\n" % f for f in re.findall(r'^def (\w+\([^)]*\)):\n    """(.*?)"""', files[m], re.M))
        parts.append(dict({"%s/%s.py" % (PKG, m): None for m in st["mods"]},
                          **{"tests/" + f: s for f, s in out.items()}, **{"stage-%d.md" % st["stage"]: order}))
    h = hashlib.sha256()
    for f in sorted(alltests):
        h.update(f.encode() + b"\0" + alltests[f].encode())
    return parts, probes, h.hexdigest()


def staged_questions(bugs):
    """Six one-word questions on stages 1 to 3, each asked by the stage and the function, not by the answer's name."""
    A = {b["stage"]: b for b in bugs if b["slot"] == "A"}
    def rate(b):
        return ("After your stage-%d fix, at what rate per unit does `%s` in `%s/%s.py` charge? (a number)"
                % (b["stage"], b["afun"], PKG, b["consumer"])), str(b["v2"])
    def module(b):
        return ("In stage %d, which module defines the name that `%s` must use? (module name, no `.py`)"
                % (b["stage"], b["afun"])), b["provider"]
    def which_s(b):
        q, a = which(b)
        return "In stage %d: %s" % (b["stage"], q), a
    qa = [rate(A[1]), which_s(A[1]), module(A[2]), which_s(A[2]), module(A[3]), rate(A[3])]
    md = "# Questions\n\nAnswer each in one word in `ANSWERS.json`: `{\"Q1\": \"...\", ..., \"Q6\": \"...\"}`.\n\n"
    md += "".join("%d. %s\n" % (i + 1, q) for i, (q, _) in enumerate(qa))
    return md, {"Q%d" % (i + 1): a for i, (_, a) in enumerate(qa)}


def write_staged(a, key):
    """The staged fixture: stage 1 in the clear, stages 2.. and QUESTIONS.md sealed in stages.bin, each opened by
    the previous stage's right results."""
    plan, bugs, files, fixed, tests = build_staged(a.seed, a.stages)
    parts, probes, tests_sha = staged_parts(plan, files, tests, a.stages)
    md, answers = staged_questions(bugs)
    g = {"__name__": "gate", "__file__": "gate.py"}
    exec(GATE, g)
    for p in parts:
        for f in p:
            if p[f] is None:
                p[f] = files[f[len(PKG) + 1:-3]]
    blobs = []
    for n, calls in enumerate(probes):
        k = g["key_of"]([c[3] for c in calls])
        pt = json.dumps(parts[n + 1] if n + 1 < len(parts) else {"QUESTIONS.md": md}).encode()
        blobs.append({"ct": base64.b64encode(g["xor"](k, pt)).decode(), "mac": hashlib.sha256(k + pt).hexdigest()[:16]})
    os.makedirs(os.path.join(a.dir, PKG))
    os.makedirs(os.path.join(a.dir, "tests"))
    w = lambda p, s: open(os.path.join(a.dir, p), "w").write(s)
    w(os.path.join(PKG, "__init__.py"), '"""ledgerkit: small ledger helpers."""\n')
    for f, s in parts[0].items():
        w(f, s)
    w(os.path.join("tests", "_trace.py"), TRACE + SEAL)
    w("TASK.md", TASK_STAGED % a.stages)
    w("gate.py", GATE.replace("PROBES = None", "PROBES = " + json.dumps([[c[:3] for c in calls] for calls in probes])))
    os.chmod(os.path.join(a.dir, "gate.py"), 0o755)
    w("stages.bin", json.dumps(blobs))
    patches = {str(st["stage"]): "".join("".join(difflib.unified_diff(
        files[m].splitlines(True), fixed[m].splitlines(True), "a/%s/%s.py" % (PKG, m), "b/%s/%s.py" % (PKG, m)))
        for m in st["mods"] if files[m] != fixed[m]) for st in plan}
    json.dump({"seed": a.seed, "stages": a.stages,
               "bugs": [{k: b[k] for k in ("n", "kind", "consumer", "provider", "stage", "slot", "v2")} for b in bugs],
               "answers": answers, "tests_sha256": tests_sha, "patches": patches,
               "patch": "".join(patches[str(n)] for n in range(1, a.stages + 1))}, open(key, "w"), indent=1)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dir")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--modules", type=int, default=24)
    ap.add_argument("--bugs", type=int, default=8)
    ap.add_argument("--stages", type=int, default=0, help="4 to 32: the staged fixture (3 modules a stage)")
    a = ap.parse_args()
    key = os.path.realpath(a.key)
    if key.startswith(os.path.realpath(a.dir) + os.sep):
        sys.exit("make-fixture: --key must be outside the fixture")
    if a.stages:
        if not 4 <= a.stages <= len(STAGE_WORDS) // STAGE_MODS:
            sys.exit("make-fixture: --stages is 4 to %d" % (len(STAGE_WORDS) // STAGE_MODS))
        return write_staged(a, key)
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

// /next: the screen registry stays navigable, creatures are deterministic, the eye sits behind one boundary and fits its box, next.css and voice.css never redefine an eye.css token.
// Run: node tests/test_next.js
"use strict";
const fs = require("fs"), path = require("path"), assert = require("assert"), { pathToFileURL } = require("url");
const ROOT = path.join(__dirname, "..", "static"), NEXT = path.join(ROOT, "next");

(async () => {
  const { SECTIONS, SCREENS } = await import(pathToFileURL(path.join(NEXT, "js", "screens.js")));
  const ids = SCREENS.map((s) => s.id);
  assert.strictEqual(new Set(ids).size, ids.length, "screen ids are unique");
  assert.ok(SECTIONS.length >= 1 && SECTIONS.length <= 5, "1 to 5 sections");
  SECTIONS.forEach((sec) => {
    const n = SCREENS.filter((s) => s.sec === sec.id).length;
    assert.ok(n >= 1 && n <= 5, sec.id + " holds 1 to 5 screens, has " + n);
    assert.ok(/<(path|rect|circle)/.test(sec.icon), sec.id + " has an SVG icon");
  });
  SCREENS.forEach((s) => {
    assert.ok(SECTIONS.some((x) => x.id === s.sec), s.id + " sits in a known section");
    assert.ok(!!s.load !== !!s.href, s.id + " has exactly one of load / href");
    if (s.load) {
      const file = s.load.startsWith("/static/") ? path.join(ROOT, s.load.slice(8)) : path.join(NEXT, "js", s.load);
      assert.ok(fs.existsSync(file), s.id + " load path exists: " + s.load);
    }
  });

  const { creature } = await import(pathToFileURL(path.join(NEXT, "js", "avatar.js")));
  assert.strictEqual(creature("a74c1565312ee1986", "working"), creature("a74c1565312ee1986", "working"), "same id draws the same creature");
  assert.notStrictEqual(creature("a74c1565312ee1986", "working"), creature("a8dd3c7ddd7003334", "working"), "different ids differ");
  assert.ok(/<svg[^>]*class="cr done"/.test(creature("x", "done")) && !/class="lid"/.test(creature("x", "done")), "done creatures sleep");
  assert.ok(/class="lid"/.test(creature("x", "working")), "working creatures have open eyes");

  const { verdict } = await import(pathToFileURL(path.join(NEXT, "js", "verdict.js")));
  const clear = verdict({ verdict: { ok: true, problems: [], asks: [], needs: [] }, events: [{ kind: "push", text: "5. Nothing needs you." }] });
  assert.deepStrictEqual([clear.text, clear.bad, clear.items, clear.keys], ["all clear", false, [], []], "no needs: all clear and an empty list");
  const two = verdict({ verdict: { needs: [{ kind: "ask", t: "2026-09-21T03:04:38+02:00", text: 'say "go TSP-019"' }, { kind: "agent", text: "agent digest exit 1" }] } });
  assert.ok(two.text === "2 need you" && two.items.length === 2 && two.keys.length === 2 && two.bad, "headline count, list and badge keys come from the same needs");
  assert.strictEqual(verdict({ verdict: { needs: [] }, errors: { sites: "timeout" } }).text, "unknown", "a failed collector reads unknown");
  const ci = "fleet nightly ci failed (no time left for a re-run before the unit timeout): exit 1 · ✖ fleet ci red: skills/a.test.sh · ~/agents/state/ci-fix/2026-10-21.md";
  const rows = verdict({ verdict: { needs: [{ kind: "push", t: "2026-10-21T03:51:22+02:00", text: ci }, { kind: "todo", todo: "27", text: "Commit the untracked files the fleet needs in ~/agents (one commit, 385 files)" }, { kind: "agent", text: "x".repeat(90) }] } }).rows;
  assert.deepStrictEqual(rows.map((r) => r.head), ["fleet nightly ci failed", "Commit the untracked files the fleet needs in ~/agents", "x".repeat(59) + "…"], "each need is its first clause, at most 60 characters");
  assert.ok(rows[0].full === ci && rows[0].t && rows[1].tag === "to do" && rows.every((r) => r.head.length <= 60), "the full server text and age ride along unchanged");
  const { linked } = await import(pathToFileURL(path.join(NEXT, "js", "verdict.js")));
  assert.strictEqual(linked('see ~/drop/T1/a&b "x".png, then (~/drop/T2/r.jpg).'), 'see <a href="/files/T1/a%26b" target="_blank" rel="noopener">~/drop/T1/a&amp;b</a> &quot;x&quot;.png, then (<a href="/files/T2/r.jpg" target="_blank" rel="noopener">~/drop/T2/r.jpg</a>).', "~/drop paths link with an encoded href, escaped text and trailing punctuation left outside");
  assert.strictEqual(linked("<b> ~/agents/state/x.md"), "&lt;b&gt; ~/agents/state/x.md", "text without a ~/drop path is only escaped");
  assert.strictEqual(linked("red · ~/agents/state/ci-fix/2026-10-21.md."), 'red · <a href="/report/agents/state/ci-fix/2026-10-21.md" target="_blank" rel="noopener">~/agents/state/ci-fix/2026-10-21.md</a>.', "a ci-fix note links into /report");
  assert.ok(["~/agents/log/ailearning-ci.log", "~/agents/sentinel-digest/REPORT.md", "~/agents/sentinel/logs/x.log"].every((p) => linked(p).includes('href="/report/agents/' + p.slice(9) + '"')), "logs and REPORT.md link into /report");
  assert.ok(["~/agents/log/m.md", "~/agents/.x/REPORT.md", "~/agents/secrets", "~/agents/secrets/REPORT.md", "~/agents/backups/REPORT.md"].every((p) => !linked(p).includes("<a")), "paths /report does not serve stay text");
  const one = verdict({ verdict: { needs: [{ kind: "agent", text: "keepalive.claude exit 1" }] } }).rows[0];
  assert.ok(one.head === one.full, "a one-clause need has head === full, so the overview renders it without an expand");

  const { EYE, fitEye, FACE, ORBIT } = await import(pathToFileURL(path.join(NEXT, "js", "gl", "eye.js")));
  assert.ok(EYE.name && typeof EYE.create === "function" && /void main\(\)/.test(EYE.fs) && /uRing/.test((EYE.vs || "") + EYE.fs), "the eye boundary exports one variant whose shaders read the data rings");
  for (const [b, o] of [[{ left: 16, top: 90, width: 368, height: 420 }, { outer: 2.75, n: ORBIT, lift: 0.55, pad: 0.1 }], [{ left: 0, top: 0, width: 900, height: 500 }, { outer: 1.6, n: FACE }]]) {
    const f = fitEye(b, o);
    assert.ok(f.r > 4 && f.x - f.r >= b.left && f.x + f.r <= b.left + b.width && f.y - f.r >= b.top && f.y + f.r <= b.top + b.height, "fitEye keeps the eye inside its box");
  }

  const tokens = (css) => new Set([...(/:root\s*{([^}]*)}/.exec(css) || [, ""])[1].matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]));
  const eye = tokens(fs.readFileSync(path.join(ROOT, "eye.css"), "utf8"));
  for (const f of ["next.css", "voice.css"]) {
    const css = fs.readFileSync(path.join(NEXT, f), "utf8");
    const clash = [...css.matchAll(/:root\s*{([^}]*)}/g)].flatMap((m) => [...m[1].matchAll(/(--[\w-]+)\s*:/g)].map((x) => x[1])).filter((t) => eye.has(t));
    assert.deepStrictEqual(clash, [], f + " redefines no eye.css token");
    assert.ok(!/#[0-9a-f]{3,8}\b/i.test(css.replace(/\/\*[\s\S]*?\*\//g, "")), f + " has no hex colour literals");
  }
  console.log("ok · " + SCREENS.length + " screens in " + SECTIONS.length + " sections · creatures deterministic · eye boundary and fit · tokens from eye.css");
})().catch((e) => { console.error(e); process.exit(1); });

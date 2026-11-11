// Office section status (T1687, owner 2026-11-11: "put a status to the sections in the office, like Vacation"): a seat or team with a
// status ({id, label, since?, note?} from /api/office) rests: its room key and only its chunk change, its board shows the label, its card
// and list entry say it; rooms without a status build exactly as before. Pure, under node: no DOM, no WebGL.
// Run: node tests/test_office_status.js
"use strict";
process.env.TZ = "UTC";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const FIX = require("./fixtures/office.json");
const ROOT = path.join(__dirname, "..");
require("module").registerHooks({ resolve: (spec, ctx, next) => next(spec.startsWith("/static/") ? pathToFileURL(path.join(ROOT, spec)).href : spec, ctx) });

const JS = path.join(__dirname, "..", "static", "next", "js");
const NOW = Date.parse("2026-11-10T15:00:00Z");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [...text].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });
/* The list's Familiars add their stylesheet and a visibility hook on load: a stub document is enough for its HTML. */
globalThis.document ??= { querySelector: () => true, hidden: false, documentElement: { classList: { toggle() {} } }, addEventListener() {} };
const PAUSED = { id: "paused", label: "Paused", since: "2026-11-11", note: "Contract ended" };
let n = 0;
const ok = (name, fn) => { fn(); console.log("ok " + ++n + " " + name); };

/* The fixture with vass paused and the quality team on vacation. */
function resting() {
  const P = JSON.parse(JSON.stringify(FIX));
  P.seats.find((s) => s.id === "vass").status = PAUSED;
  P.staff.find((t) => t.id === "quality").status = { id: "vacation", label: "On vacation" };
  return P;
}
/* A chunk as comparable data: geometry, baked colours, lamps, quads, labels, creatures. */
const flat = (c) => JSON.stringify([[...c.position], [...c.color], [...c.index], c.lamps, c.quads, c.labels, c.actors.map((a) => ({ ...a, light: [...(a.light || [])] }))]);

(async () => {
  const Mo = await load("office/model.js"), L = await load("office/layout.js"), Bd = await load("office/build/index.js"), F = await load("office/fields.js");
  const { tiers } = await load("office/tier.js"), { list } = await load("office/overlay/list.js"), { THEME } = await load("office/theme.js");
  const { decode } = await load("office/kit.js"), kit = decode(require("../static/next/office/kit.json")), T = await load("office/time.js");
  const A = Mo.build(FIX, { now: NOW, needs: false }), B = Mo.build(resting(), { now: NOW, needs: false });
  const room = (M, id) => [M.ceo, ...M.rooms, ...M.staff].find((r) => r.id === id);

  ok("model: a room carries its section's status, null while active; the key changes only for the resting rooms", () => {
    assert.deepStrictEqual(room(B, "vass").status, PAUSED);
    assert.strictEqual(room(B, "team-quality").status.label, "On vacation");
    assert.strictEqual(room(A, "vass").status, null);
    assert.strictEqual(room(B, "mooblox").status, null);
    const changed = [B.ceo, ...B.rooms, ...B.staff].filter((r) => r.key !== room(A, r.id).key).map((r) => r.id);
    assert.deepStrictEqual(changed, ["vass", "team-quality"]);
  });

  ok("diff: setting a status rebuilds only that room, no layout change, no person changes", () => {
    const d = Mo.diff(A, B);
    assert.deepStrictEqual([d.layout, d.night, d.rooms, d.people], [false, false, ["vass", "team-quality"], []]);
  });

  ok("time: day() writes a calendar date as D Mon, with the year when not this year's", () => {
    assert.strictEqual(T.day("2026-11-11", NOW), "11 Nov");
    assert.strictEqual(T.day("2025-03-02", NOW), "2 Mar 2025");
  });

  ok("cards: the room card's state line leads with the status and since, the note is its first line", () => {
    const r = F.card(room(B, "vass"), NOW), t = F.card(room(B, "team-quality"), NOW);
    assert.strictEqual(r.state.text, "Paused since 11 Nov · " + room(B, "vass").busy + " working now");
    assert.strictEqual(r.lines[0], "Contract ended");
    assert.strictEqual(tiers(r).top.lines[0], "Contract ended");
    assert.strictEqual(t.state.text, "On vacation · " + room(B, "team-quality").busy + " working now");
    assert.deepStrictEqual(F.card(room(B, "mooblox"), NOW), F.card(room(A, "mooblox"), NOW), "an active room's card is unchanged");
    assert.deepStrictEqual(F.card(room(A, "vass"), NOW).state.text, room(A, "vass").busy + " working now");
  });

  ok("builders: the resting rooms' boards show the label in the rest colour; every other chunk is the same as without any status", () => {
    const PA = L.plan(A), PB = L.plan(B);
    assert.deepStrictEqual(PA, PB, "a status moves no room");
    for (const r of [A.ceo, ...A.rooms, ...A.staff]) {
      const a = Bd.chunk(r.id, A, PA, THEME, kit, ink), b = Bd.chunk(r.id, B, PB, THEME, kit, ink), same = flat(a) === flat(b);
      assert.strictEqual(same, !["vass", "team-quality"].includes(r.id), r.id + (same ? " unchanged" : " changed"));
    }
    const v = Bd.chunk("vass", B, PB, THEME, kit, ink), board = v.labels.filter((l) => l.quad);
    assert.strictEqual(board.length, 1, "still one board, one tap target");
    const restInk = THEME.rest.map((c) => c * 0.6 + 0.4).join();
    assert.ok(v.quads.some((q) => q.col && q.col.join() === restInk), "the status label is drawn in the rest colour");
    assert.ok(!Bd.chunk("vass", A, PA, THEME, kit, ink).quads.some((q) => q.col && q.col.join() === restInk), "no label without a status");
  });

  ok("list: a resting seat and team carry a status tag and the rest class; active ones none", () => {
    const h = list(B), a = list(A);
    assert.ok(/class="seat rest" data-seat="vass"/.test(h) && />Paused<\/span>/.test(h), "vass tagged Paused");
    assert.ok(/class="team rest"/.test(h) && />On vacation<\/span>/.test(h), "quality tagged On vacation");
    assert.strictEqual((h.match(/class="ost"/g) || []).length, 2);
    assert.ok(!/class="ost"|rest"/.test(a), "no tag without a status");
  });
  console.log(`${n} passed`);
})().catch((e) => { console.error(e); process.exit(1); });

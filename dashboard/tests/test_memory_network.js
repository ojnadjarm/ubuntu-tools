// Library › Memory › Network (T1624-R7) on a synthetic fixture store (every fact invented; a selftest proves it is not the real store):
// the routes against the CLI (`memory net export --json`, `memory recall --explain` for 3 prompts, run as the owner's own session),
// no PRIVATE text in any JSON, then the tab in a headless browser at 400, 768, 1366, 1920, 2560 (no sideways scroll, symmetric
// margins, every star drawn, the try box shows the CLI's hints), then `resp-check` at the same widths.
// Run: node tests/test_memory_network.js   (SHOTS=<dir> writes net-<w>.png and try-<w>.png)
"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path"), cp = require("child_process");
const { chromium, serveStatic } = require("./lib/browser");
const DASH = path.resolve(__dirname, ".."), AGENTS = path.dirname(DASH), MEM = path.join(AGENTS, "bin", "memory"), LIB = path.join(AGENTS, "lib");
const HOME_OF = (env) => cp.execFileSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())", LIB], { env, encoding: "utf8" }).trim();
const real = (d) => { try { return fs.realpathSync(d); } catch (e) { return path.resolve(d); } }, REAL = real(HOME_OF(process.env));
const T = fs.mkdtempSync(path.join(os.tmpdir(), "memnet."));
const env = { ...process.env, HOME: T + "/home", AGENT_WORK: T + "/aw", MEMORY_HOME: T + "/store", XDG_RUNTIME_DIR: T + "/run", HARNESS_CONFIG: "/nonexistent", CHAT_SEAT: "boss" };
for (const k of ["MEMORY_WORKER", "MEMORY_DOMAINS", "MEMORY_RECALL", "MEMORY_RECALL_DONE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CONFIG_DIR"]) delete env[k];
const SECRET = ["zanzibar", "quokka", "blue folder", "spare key", "beans"];
const PROMPTS = ["watering tomatoes at dusk near clay storm drains", "harbour lantern at the last crossing, pigeon relay from the tower at noon", "zanzibar folder spare key under the quokka mat"];
const PAGES = {
  "domains.map": "seat:boss secret owner\n~/garden garden\n",
  "core/CORE.md": "# Core: fixture\n- Answers stay short and plain. (26-10-01) → craft ^c01\n",
  "core/craft.md": "# Craft\n- Short answers lead with the result, then one reason. (26-10-01) ^c02\n",
  "domains/garden/DOMAIN.md": "# Garden card\n- Tomatoes hate wet leaves at night. (26-10-05) → soil ^g01\n- Compost turns faster with shredded cardboard. (26-10-07) ^g03\n",
  "domains/garden/soil.md": "# Soil\n- Watering tomatoes at dusk invites blight and grey mould on every lower leaf. (26-10-05) ^s01\n- Clay drains slowly after a storm. (26-10-08) ^s02\n",
  "domains/coast/DOMAIN.md": "# Coast card\n- The harbour lantern is lit at the last crossing. (26-10-10) ^h01\n- Ferry tickets are sold at the harbour kiosk. (26-10-11) ^h02\n",
  "domains/relay/DOMAIN.md": "# Relay card\n- Tower routine is in the tower file. (26-10-10) → tower ^r00\n",
  "domains/relay/tower.md": "# Tower\n- Pigeon relay messages leave at noon from the tower. (26-10-10) ^r01\n",
  "domains/secret/DOMAIN.md": "PRIVATE: boss\n# Secret card\n- Zanzibar vault code sits in the blue folder. (26-10-01) ^x01\n",
  "domains/secret/more.md": "# More\n- Zanzibar folder spare key hides under the quokka mat, 12 beans. (26-10-01) ^x02\n",
};
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];

// Routes through the dashboard's own handlers, and the CLI run as a grandchild of init (a `claude -p` ancestor would make it a worker).
const PY = String.raw`
import json, os, subprocess, sys, urllib.parse
dash, mem, home, prompts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
sys.path.insert(0, dash)
import server  # noqa: F401
from dash.services import memory

def call(fn, url, ip="127.0.0.1"):
    out = []
    h = type("H", (), {"path": url, "client_address": (ip, 0), "headers": {}, "json": lambda self, o, code=200: out.append((code, o))})()
    fn(h, url.partition("?")[0])
    return {"code": out[-1][0], "body": out[-1][1]}

def orphan(argv):
    r, w = os.pipe()
    if os.fork() == 0:
        os.setsid()
        if os.fork() == 0:
            os.dup2(w, 1); os.close(r); os.close(w); os.chdir(home); os.execv(argv[0], argv)
        os._exit(0)
    os.close(w); os.wait()
    with os.fdopen(r) as f:
        return f.read()

def fmt(h):
    return f"^{h['id']} · {h['place']} · {h['activation']}" + ("" if h["why"] is None else " · " + " | ".join(h["why"]))

tries = {q: call(memory.try_route, "/api/memory/net/try?q=" + urllib.parse.quote(q)) for q in prompts}
explain = {q: orphan([mem, "recall", "--explain", q]) for q in prompts}
print(json.dumps({"net": call(memory.net_route, "/api/memory/net"), "lan": call(memory.net_route, "/api/memory/net", "192.0.2.10")["code"],
  "empty": call(memory.try_route, "/api/memory/net/try?q=%20")["code"], "tries": tries,
  "cli": {q: {"block": e.split("cues · ")[0], "hints": e.split("cues · ", 1)[1].split("\n")[1:-1]} for q, e in explain.items()},
  "route": {q: {"block": t["body"]["block"], "hints": [fmt(h) for h in t["body"]["hints"]]} for q, t in tries.items()},
  "export": json.loads(orphan([mem, "net", "export", "--json"]))}))
`;

(async () => {
  const home = HOME_OF(env);
  assert.ok(home === env.MEMORY_HOME && real(home) !== REAL, "selftest: MEMORY_HOME is the throwaway store, not the real one");
  for (const [rel, text] of Object.entries(PAGES)) { fs.mkdirSync(path.dirname(path.join(env.MEMORY_HOME, rel)), { recursive: true }); fs.writeFileSync(path.join(env.MEMORY_HOME, rel), text); }
  for (const d of [env.HOME + "/garden", env.AGENT_WORK, env.XDG_RUNTIME_DIR]) fs.mkdirSync(d, { recursive: true });
  cp.execFileSync(MEM, ["net", "build"], { env, cwd: T, stdio: "ignore" });
  const R = JSON.parse(cp.execFileSync("python3", ["-c", PY, DASH, MEM, env.HOME, ...PROMPTS], { env, cwd: T, encoding: "utf8" }));

  const net = R.net.body, ids = net.memories.map((m) => m[0]);
  assert.strictEqual(R.net.code, 200, "GET /api/memory/net 200");
  assert.strictEqual(R.lan, 403, "the LAN gets 403");
  assert.strictEqual(R.empty, 400, "an empty prompt is 400");
  assert.deepStrictEqual(R.export, net, "memory net export --json = GET /api/memory/net");
  assert.ok(net.built && ids.includes("s01") && ids.includes("c02") && !ids.includes("x01") && !ids.includes("x02"), "public memories only: " + ids);
  assert.deepStrictEqual(net.places.filter((p) => p.private).map((p) => p.place), ["domains/secret/DOMAIN.md", "domains/secret/more.md"], "PRIVATE pages by name only");
  for (const [what, body] of [["net", net], ...PROMPTS.map((q) => ["try " + q.slice(0, 20), R.tries[q].body])]) {
    const s = JSON.stringify(body).toLowerCase();
    for (const w of SECRET) assert.ok(!s.includes(w), `${what}: no PRIVATE text ("${w}")`);
  }
  for (const q of PROMPTS) {
    assert.strictEqual(R.tries[q].code, 200, q + ": 200");
    assert.deepStrictEqual(R.route[q], R.cli[q], `try box = memory recall --explain for "${q}"`);
  }
  assert.ok(R.route[PROMPTS[0]].hints.length && R.route[PROMPTS[1]].hints.length, "prompts 1 and 2 fire");
  assert.deepStrictEqual(R.tries[PROMPTS[2]].body.hints.map((h) => [h.id, h.why]), [["x02", null]], "prompt 3: the private memory as id and place only");
  console.log(`routes = CLI for ${PROMPTS.length} prompts (${PROMPTS.map((q) => R.route[q].hints.length).join("/")} hints) · export = route · no PRIVATE text · LAN 403`);

  const srv = serveStatic((u, res) => {
    if (u === "/api/status") return { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
    if (u === "/api/memory") return { count: 1, private: 0, pages: [{ page: "core/CORE.md", bytes: 10, mtime: 1794261588 }] };
    if (u === "/api/memory/net") return net;
    if (u === "/api/memory/net/try") {
      const t = R.tries[new URL(res.req.url, "http://x").searchParams.get("q")];
      if (!t) { res.writeHead(400, { "Content-Type": "application/json" }); res.end('{"error":"unknown fixture prompt"}'); return; }
      return t.body;
    }
  });
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    for (const [w, h] of SIZES) {
      const touch = w <= 768;
      const ctx = await b.newContext({ viewport: { width: w, height: h }, reducedMotion: "reduce", hasTouch: touch, isMobile: touch });
      const p = await ctx.newPage(), errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      await p.goto(base + "/#memory?v=net");
      await p.waitForFunction((n) => (document.querySelector(".mem .mnsky canvas") || { dataset: {} }).dataset.stars === String(n), ids.length, { timeout: 15000 });
      const look = () => p.evaluate(() => {
        const g = document.querySelector(".mem .mngrid").getBoundingClientRect(), sky = document.querySelector(".mem .mnsky"), c = sky.querySelector("canvas");
        return { sw: document.documentElement.scrollWidth, left: g.left, right: document.documentElement.clientWidth - g.right,
          cw: c.getBoundingClientRect().width, sky: sky.clientWidth, tab: document.querySelector('.mem .mtab[aria-current="page"]').textContent,
          tabs: [...document.querySelectorAll(".mem .mtab")].map((a) => [a.getAttribute("href"), Math.round(a.getBoundingClientRect().height)]),
          text: document.body.innerText.toLowerCase(), hash: location.hash };
      });
      const a = await look();
      assert.strictEqual(a.sw, w, w + ": no sideways scroll");
      assert.ok(Math.abs(a.left - a.right) <= 2, `${w}: symmetric margins ${a.left} / ${a.right}`);
      assert.ok(Math.abs(a.cw - a.sky) < 1, `${w}: the canvas fills its box (${a.cw} in ${a.sky})`);
      assert.strictEqual(a.tab, "network", w + ": Network tab current");
      assert.strictEqual(a.hash, "#memory?v=net", w + ": hash");
      if (touch) assert.ok(a.tabs.every(([, ht]) => ht >= 44), w + ": tabs 44 px on touch " + a.tabs);
      for (const s of SECRET) assert.ok(!a.text.includes(s), `${w}: no PRIVATE text on the page ("${s}")`);
      if (process.env.SHOTS) await p.screenshot({ path: `${process.env.SHOTS}/net-${w}.png`, fullPage: true });
      if (w === 400 || w === 1366) {
        for (const q of PROMPTS) {
          await p.fill("#mnq", q);
          await p.press("#mnq", "Enter");
          await p.waitForFunction(() => !/firing/.test(document.querySelector(".mem .mnout").textContent) && /cues/.test(document.querySelector(".mem .mnout").textContent), null, { timeout: 15000 });
          const shown = await p.evaluate(() => ({ hints: [...document.querySelectorAll(".mem .mnhints li")].map((li) => [li.dataset.id, li.querySelector(".pl").textContent, li.querySelector(".why").textContent]),
            block: (document.querySelector(".mem .mnblock") || {}).textContent || "", lit: document.querySelector(".mem .mnsky canvas").dataset.lit, sw: document.documentElement.scrollWidth }));
          const want = R.tries[q].body.hints.map((x) => [x.id, x.place, x.why ? x.why.join(" | ") : "private · id and place only"]);
          assert.deepStrictEqual(shown.hints, want, `${w}: the try box shows the CLI's hints for "${q}"`);
          assert.strictEqual(shown.block, R.tries[q].body.block, `${w}: the block as the agent sees it`);
          assert.strictEqual(shown.lit, R.tries[q].body.hints.filter((x) => ids.includes(x.id)).map((x) => x.id).join(" "), `${w}: public fired stars lit on the sky`);
          assert.strictEqual(shown.sw, w, `${w}: no sideways scroll after a try`);
          if (process.env.SHOTS && q === PROMPTS[0]) await p.screenshot({ path: `${process.env.SHOTS}/try-${w}.png`, fullPage: true });
        }
        await p.click('.mem .mtab[data-mv=""]');
        await p.waitForFunction(() => location.hash === "#memory" && document.querySelector(".mem .mlist"), null, { timeout: 15000 });
      }
      assert.deepStrictEqual(errs, [], w + ": page errors");
      await ctx.close();
    }
    console.log("network tab: 5 widths · every star drawn · no sideways scroll · symmetric margins · try box = CLI hints at 400 and 1366");
    const rc = await new Promise((ok) => cp.execFile("resp-check", [base + "/#memory?v=net"], { timeout: 180000 }, (e, out, err) => ok({ status: e ? e.code : 0, out, err })));
    process.stdout.write(rc.out);
    assert.strictEqual(rc.status, 0, "resp-check passes at 400, 768, 1366, 1920, 2560 (async: the fixture server lives in this process): " + rc.err);
  } finally { await b.close(); srv.close(); fs.rmSync(T, { recursive: true, force: true }); }
})().catch((e) => { console.error(e.message); try { fs.rmSync(T, { recursive: true, force: true }); } catch (x) {} process.exit(1); });


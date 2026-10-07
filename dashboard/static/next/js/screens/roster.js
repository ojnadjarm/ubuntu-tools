/* Roster: the eye asleep, one countdown ring per scheduled agent; each sleeper rides its ring's head towards its next run. */
import { esc, when } from "/static/js/core/fmt.js";
import { creature } from "../avatar.js";
import { dust } from "../shapes.js";
import { fitEye, FACE } from "../gl/cam.js";
import { lens, odo } from "../ui/num.js";
import { store } from "../store.js";
import { ago, until } from "./court.js";

export const own = true;
const R0 = 1.34, DR = 0.24;
const list = () => ((store.A || {}).roster || []).filter((r) => r.name !== "hello");
const bad = (r) => r.health ? r.health === "bad" : !!(r.last && r.last.exit && r.last.exit !== "0");
const on = (r) => (r.on == null ? r.enabled === "enabled" : r.on);
const timed = (r) => on(r) && r.kind !== "service";
/* How far the agent is from its last run to its next one, in percent. */
const progress = (r) => { const a = Date.parse((r.last || {}).end), b = Date.parse(r.next); return a && b && b > a ? Math.max(0, Math.min(100, (100 * (Date.now() - a)) / (b - a))) : 0; };
const num = (k, s) => { const m = /^([\d.]+)(.*)$/.exec(s); return m ? odo(k, m[1]) + esc(m[2]) : esc(s); };

export function render(grid, D) {
  if (!store.A) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">reading the roster…</p></div>`;
  const L = list(), up = L.filter(on), soon = up.filter((r) => r.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next))[0];
  const q = up.filter((r) => r.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next));
  return `<div class="nxs roster"><section class="rhead"><div class="shelf" id="shelf" aria-hidden="true"></div><div class="rt"><p class="kin" data-dec>Roster</p>` +
    `<p class="bsum">${up.length} of ${L.length} agents on${soon ? ` · next up <b>${esc(soon.name)}</b> in ${num("ro.soon", until(soon.next))}` : ""}</p>` +
    `<ol class="soon" aria-label="next runs, soonest first">${q.map((r) => `<li class="${bad(r) ? "bad" : ""}"><b>${esc(r.name)}</b><span>in ${num("ro.q" + r.name, until(r.next))}</span><i style="--v:${(progress(r) / 100).toFixed(3)}" aria-hidden="true"></i></li>`).join("")}</ol></div></section><div class="rcards">` +
    L.map(card).join("") + `</div></div>`;
}

const last = (l) => (l && l.end ? esc(when(l.end)) + " · " + ago(l.end) + " ago" : "never");
const exit = (l, b) => { const ex = l && l.exit; return `<dd class="${b ? "gold" : ""}">${ex == null || ex === "" ? "—" : esc(ex)}${l && l.seconds ? " · " + esc(l.seconds) + " s" : ""}</dd>`; };
const head = (r, b, pill, cls, meta) => `<article class="pane ragent${b ? " bad" : r.health === "warn" ? " warn" : ""}${on(r) ? "" : " off"}"><div class="av" aria-hidden="true">${creature(r.name, b ? "error" : "sleep")}</div><div class="bd"><h3><b data-dec>${esc(r.name)}</b></h3>` +
  `<p class="meta"><span class="pill ${cls}">${pill}</span> ${meta}</p></div>`;
const foot = (r, pre = "") => `<p class="doing">${r.report ? pre + esc(r.report) : "no report yet"}</p></article>`;

/* agent@<name>.timer: countdown ring to the next run. */
function timerCard(r) {
  const run = on(r), b = bad(r), p = run ? progress(r) : 0;
  return head(r, b, run ? "scheduled" : "off", run ? "running" : "idle", esc(r.schedule || "no schedule")) +
    lens(p, run && r.next ? num("ro.n" + r.name, until(r.next)) : "off", `${r.name}: ${run && r.next ? Math.round(p) + " % of the wait to the next run" : "not scheduled"}`, b) +
    `<dl class="kv"><dt>next</dt><dd>${run && r.next ? esc(when(r.next)) : "—"}</dd><dt>last run</dt><dd>${last(r.last)}</dd><dt>last exit</dt>${exit(r.last, b)}</dl>` + foot(r);
}

/* A bash timer does the work; the agent is its fallback. */
function bashCard(r) {
  const u = r.runner || {}, run = on(r), b = bad(r), p = run ? progress(r) : 0, fb = r.fallback || {};
  return head(r, b, run ? (b ? "failed" : "on") : "down", run ? (b ? "failed" : "running") : "down", `${esc(r.schedule || "—")} · <span class="unit">${esc(u.unit || "")}</span>`) +
    lens(p, run && r.next ? num("ro.n" + r.name, until(r.next)) : "down", `${r.name}: ${run && r.next ? Math.round(p) + " % of the wait to the next check" : "timer not running"}`, b) +
    `<dl class="kv"><dt>next</dt><dd>${run && r.next ? esc(when(r.next)) : "—"}</dd><dt>last check</dt><dd>${last(r.last)}</dd><dt>result</dt>${exit(r.last, b)}</dl>` +
    `<p class="fb">fallback agent last ran ${fb.end ? esc(when(fb.end)) + " · " + ago(fb.end) + " ago" : "never"}</p>` + foot(r, "fallback report: ");
}

/* An always-on service: on while its unit is active and its tmux session lives. */
function serviceCard(r) {
  const u = r.runner || {}, run = on(r), b = bad(r), w = r.health === "warn";
  const pill = run ? "on" : b ? "failed" : w ? "down" : "off";
  return head(r, b, pill, run ? "running" : b ? "failed" : w ? "down" : "idle", `always on · <span class="unit">${esc(u.unit || "")}</span>`) +
    lens(run ? 100 : 0, run && u.since ? num("ro.n" + r.name, ago(u.since)) : pill, `${r.name}: ${run ? "up " + ago(u.since) : pill}`, b || w) +
    `<dl class="kv"><dt>up since</dt><dd>${run && u.since ? esc(when(u.since)) : "—"}</dd><dt>unit</dt><dd class="${u.state === "active" ? "" : "gold"}">${esc(u.state || "—")}${u.sub ? " · " + esc(u.sub) : ""}</dd>` +
    (u.tmux ? `<dt>tmux</dt><dd class="${u.tmux_alive ? "" : "gold"}">${esc(u.tmux)} · ${u.tmux_alive ? "alive" : "missing"}</dd>` : "") + `</dl>` + foot(r);
}

const CARDS = { "bash-timer": bashCard, service: serviceCard };
const card = (r) => (CARDS[r.kind] || timerCard)(r);

/* The sleeping eye inside one countdown ring per scheduled agent; the agent sleeps at its ring's head. */
export function scene(D) {
  const L = list().filter(timed), narrow = innerWidth < 820, outer = R0 + DR * Math.max(0, L.length - 1);
  const G = L.map((r, i) => ({ r, p: progress(r), rad: R0 + DR * i }));
  return {
    key: JSON.stringify(G.map((g) => [g.r.name, (g.r.last || {}).end, bad(g.r)])),
    pts: dust(narrow ? 700 : 1700),
    box: document.getElementById("gl"), span: narrow ? 14 : 24, tilt: 0.3,
    eyeEl: document.getElementById("shelf"), eyeFit: (b) => fitEye(b, { outer: outer + 0.22, n: FACE, pad: 0.02 }),
    rings: G.map((g) => ({ r: g.rad, v: g.p / 100, kind: bad(g.r) ? 1 : 3 })), ringN: FACE, halo: 0, sleep: 0.6,
    creatures: G.map((g) => ({ id: g.r.name, state: bad(g.r) ? "error" : "sleep", ring: { r: g.rad, a: g.p / 100 }, size: 0.44, min: narrow ? 30 : 36 })),
  };
}

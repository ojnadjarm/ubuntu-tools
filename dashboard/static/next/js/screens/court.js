/* Court: the eye at the centre, live sub-agents orbit it on the inner ring, the persistent crew on the outer; finished ones sit in a collapsed Recent drawer. */
import { esc } from "/static/js/core/fmt.js";
import { creature } from "../avatar.js";
import { dust } from "../shapes.js";
import { fitEye, ORBIT } from "../gl/cam.js";
import { odo } from "../ui/num.js";
import { store } from "../store.js";

export const own = true;
const R1 = 1.9, R2 = 2.75;
const PILL = { working: "running", done: "idle", error: "warn", stale: "stray" };
let open = true, recent = false;

export const tk = (l) => (/^[A-Za-z]{1,3}\d+\w*(\s+[A-Za-z]{1,3}\d+\b)?/.exec(l) || [l.split(" ")[0]])[0];
export const rest = (l) => l.slice(tk(l).length).trim();
const mins = (t) => { const ms = typeof t === "number" ? t * 1000 : /^\d+$/.test(t) ? t * 1000 : Date.parse(t); return ms ? Math.max(0, (Date.now() - ms) / 60000) : NaN; };
export const ago = (t) => { const m = mins(t); return isNaN(m) ? "—" : m < 60 ? Math.round(m) + " min" : m < 2880 ? (m / 60).toFixed(1) + " h" : Math.round(m / 1440) + " d"; };
export const until = (t) => { const h = (Date.parse(t) - Date.now()) / 3600000; return isNaN(h) ? "—" : h < 1 ? Math.max(0, Math.round(h * 60)) + " min" : h < 48 ? h.toFixed(0) + " h" : (h / 24).toFixed(0) + " d"; };
const split = (A) => { const s = A.subagents || []; return { live: s.filter((x) => x.state === "working"), done: s.filter((x) => x.state !== "working") }; };
const crew = (A) => (A.roster || []).filter((r) => r.state && r.state !== "off");
/* ago() as rolling digits under key k. */
const agoOdo = (k, t) => { const a = ago(t), m = /^([\d.]+)(.*)$/.exec(a); return m ? odo(k, m[1]) + esc(m[2]) : esc(a); };

function card(s) {
  const run = s.state === "working";
  const line = run ? "now · " + (s.doing || "starting") : s.report || (s.state === "stale" ? "no report · last step · " + (s.doing || "—") : "—");
  return `<article class="nagent ${s.state}"><div class="av" aria-hidden="true">${creature(s.id, s.state)}</div><div class="bd"><h3><b data-dec>${esc(tk(s.label))}</b> ${esc(rest(s.label))}</h3>` +
    `<p class="meta"><span class="pill ${PILL[s.state]}">${s.state}</span> ${run ? "running " + agoOdo("ct.r" + s.id, s.started) : s.state === "error" ? "ended " + agoOdo("ct.e" + s.id, s.last) + " ago" : "idle " + agoOdo("ct.i" + s.id, s.last)}</p><p class="doing">${esc(line)}</p></div></article>`;
}

export function render(grid, D) {
  const A = store.A;
  if (!A) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">reading the agents…</p></div>`;
  const { live, done } = split(A), P = crew(A), up = P.filter((r) => r.state === "running").length, O = A.orchestrator || {};
  return `<div class="nxs hero agents">` +
    `<section class="pane side"><h2><span data-dec>running now</span><s>${live.length}</s></h2>${live.map(card).join("") || `<p class="sm">nobody is working · the court sleeps</p>`}` +
    `<details class="recent"${recent ? " open" : ""}><summary><h2><span data-dec>recent · 24 h</span><s>${done.length} ended</s></h2></summary><ul class="mini">${done.map((s) => `<li><span aria-hidden="true">${creature(s.id, s.state)}</span><b>${esc(tk(s.label))}</b><span>${s.state === "done" ? "" : `<i class="pill ${PILL[s.state]}">${s.state === "stale" ? "stopped" : s.state}</i> `}${esc(s.report || rest(s.label))}</span><em>${ago(s.last)}</em></li>`).join("") || `<li><span></span><b></b><span>nothing ended in the last 24 h</span></li>`}</ul></details></section>` +
    `<div class="court" id="court"><div class="ring" id="ring" aria-hidden="true"></div><button class="orch" id="orch" type="button" aria-expanded="${open}" aria-controls="court"><b>${esc(O.name || "DarkSaddler")}</b><span>orchestrator · ${esc(O.state || "idle")} · ${odo("ct.w", String(live.length))} working</span></button></div>` +
    `<section class="pane side"><h2><span data-dec>persistent</span><s>${up} running · ${P.length}</s></h2><ul class="mini">${P.map((r) => `<li><span aria-hidden="true">${creature(r.name, r.state === "running" ? "working" : "sleep")}</span><b>${esc(r.name)}</b><span><i class="pill ${r.state}">${r.state}</i> ${r.next ? "next " + until(r.next) : r.enabled === "enabled" ? "—" : "always on"}</span><em>${r.last && r.last.end ? ago(r.last.end) : ""}</em></li>`).join("")}</ul>` +
    `<h2 class="sub2"><span data-dec>claims board</span><s>${(A.claims || []).length}</s></h2><ul class="claims">${(A.claims || []).map((c) => { const p = c.split(" · "); return `<li>${esc(p[0])} <span>${esc(p.slice(1).join(" · "))}</span></li>`; }).join("") || `<li><span>empty · nobody holds a file</span></li>`}</ul></section></div>`;
}

/* Live agents ride the inner ring from the front-right, the persistent crew spreads round the outer ring, asleep while idle; the rings turn only while someone works. */
function crowd(A, narrow) {
  const { live } = split(A), P = crew(A);
  return [
    ...live.map((s, i) => ({ id: s.id, state: s.state, ring: { r: R1, a: 0.36 + i / Math.max(1, live.length) }, dir: 1, size: 0.72, min: narrow ? 44 : 56, big: true, tag: `<b>${esc(tk(s.label))}</b> · ${ago(s.started)}` })),
    ...P.map((r, i) => ({ id: r.name, state: r.state === "running" ? "working" : "sleep", ring: { r: R2, a: 0.1 + i / P.length }, dir: -1, size: 0.5, min: narrow ? 26 : 36, tag: `<b>${esc(r.name)}</b>` })),
  ];
}

export function scene(D) {
  const A = store.A || { subagents: [] }, narrow = innerWidth < 820, cr = open ? crowd(A, narrow) : [];
  return {
    key: JSON.stringify([open, cr.map((c) => [c.id, c.state])]),
    pts: dust(narrow ? 700 : 1600),
    box: document.getElementById("gl"), span: narrow ? 14 : 24, tilt: 0.2,
    eyeEl: document.getElementById("ring"), eyeFit: (b) => fitEye(b, open ? { outer: R2, n: ORBIT, lift: 0.55, pad: narrow ? 0.1 : 0.03 } : { halo: true, pad: 0.1, cap: b.height * 0.3 }),
    rings: open ? [{ r: R1, v: 1, kind: 2 }, { r: R2, v: 1, kind: 2 }] : [], ringN: ORBIT, halo: open ? 0 : 1,
    orbit: open && cr.some((c) => c.state === "working"), creatures: cr, pulse: "done",
  };
}

export function click(e) {
  const sm = e.target.closest(".recent > summary");
  if (sm) { recent = !sm.parentNode.open; return false; }
  const b = e.target.closest("#orch");
  if (!b) return false;
  open = !open;
  b.setAttribute("aria-expanded", String(open));
  store.rescene();
  return true;
}

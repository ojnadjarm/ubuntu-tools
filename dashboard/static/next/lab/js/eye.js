/* Eye lab page: the variant from ?v=, pointer and touch, event buttons, live load and agents from the panel APIs, and a capture hook. */
import { createEngine, still } from "./engine.js";
import { createLife } from "./life.js";
import { variantA } from "./eye-a.js";
import { variantB } from "./eye-b.js";
import { variantC } from "./eye-c.js";

const VARIANTS = { a: variantA, b: variantB, c: variantC };
const q = new URLSearchParams(location.search);
const key = VARIANTS[q.get("v")] ? q.get("v") : "a";
const capture = q.has("capture"), embed = q.has("embed");
if (embed) document.body.classList.add("embed");
const stage = document.getElementById("stage");
const $ = (id) => document.getElementById(id);

const life = createLife({ seed: +(q.get("seed") || 7), still: still.matches });
const box = () => {
  const b = stage.getBoundingClientRect();
  return { x: b.left + b.width / 2, y: b.top + b.height / 2, r: embed ? Math.min(b.width / 3.3, b.height / 2.6) : Math.min(b.width / (b.width < 700 ? 2.3 : 3.8), b.height / 2.2) };
};
const eng = createEngine($("gl"), { variant: VARIANTS[key](), life, box, capture, tier: q.get("tier") || undefined, idleFps: +(q.get("idle") ?? (embed ? 0 : 4)) });
document.body.dataset.v = key;
document.querySelectorAll("[data-v]").forEach((a) => a.setAttribute("aria-current", a.dataset.v === key ? "page" : "false"));

const toEye = (x, y) => { const b = box(); return [(x - b.x) / b.r, (b.y - y) / b.r]; };
const clock = () => eng.clock();

if (!capture) {
  addEventListener("pointermove", (e) => { if (still.matches) return; const [u, v] = toEye(e.clientX, e.clientY); life.setPointer(u, v, clock()); eng.wake(400); }, { passive: true });
  document.documentElement.addEventListener("pointerleave", () => { if (still.matches) return; life.setPointer(null, null, clock()); eng.wake(300); });
  addEventListener("pointerdown", (e) => {
    if (still.matches) return;
    const [u, v] = toEye(e.clientX, e.clientY);
    life.setPointer(u, v, clock());
    if (Math.hypot(u, v * 1.6) < 0.9) life.event("poke", u, v, clock());
    eng.wake(600);
  }, { passive: true });
  document.querySelectorAll("[data-ev]").forEach((b) => b.addEventListener("click", (e) => {
    e.stopPropagation();
    const r = b.getBoundingClientRect(), [u, v] = toEye(r.left + r.width / 2, r.top + r.height / 2);
    life.event(b.dataset.ev, u, v, clock());
    eng.wake(1600);
  }));
  $("load").addEventListener("input", (e) => { life.setData({ load: e.target.value / 100 }); live(); eng.wake(1200); });
}

let agentsOn = 0, cpu = null;
function live() {
  const l = Math.round(life.load * 100);
  $("live").textContent = `cpu ${cpu == null ? "…" : cpu.toFixed(1) + " %"} · pupil ${l} % · agents working ${agentsOn}`;
}
async function poll() {
  if (document.hidden || capture) return;
  try {
    const s = await (await fetch("/api/status")).json();
    const v = s.sparks && s.sparks.cpu && s.sparks.cpu.values;
    if (v && v.length) { cpu = v[v.length - 1]; life.setData({ load: Math.min(1, cpu / 40) }); $("load").value = Math.round(life.load * 100); }
  } catch { /* offline: keep the last value */ }
  try {
    const a = await (await fetch("/api/agents")).json();
    const working = (a.subagents || []).filter((x) => x.state === "working");
    const done = (a.subagents || []).filter((x) => x.state === "done").map((x) => x.id);
    if (poll.done && done.some((id) => !poll.done.includes(id))) { life.event("done", -1.4, 0.4, clock()); eng.wake(1600); }
    poll.done = done;
    agentsOn = working.length;
    life.setData({ act: Math.min(1, agentsOn / 3) });
  } catch { /* no agents api */ }
  live();
  eng.wake(0);
}
if (!capture) { poll(); setInterval(poll, 30000); document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); }); }
live();

if (q.has("hud")) {
  const hud = $("hud"); hud.hidden = false;
  let f0 = 0, t0 = performance.now();
  setInterval(() => { const S = eng.S, n = S.frames - f0, dt = (performance.now() - t0) / 1000; f0 = S.frames; t0 = performance.now();
    hud.textContent = `${key} · tier ${S.tier} · scale ${S.scale.toFixed(2)} · ${(n / dt).toFixed(1)} fps · probe ${S.probeMs} ms · ${S.hdr ? S.hdr.width + "×" + S.hdr.height : ""}`; }, 1000);
}

window.__lab = { eng, life, S: eng.S, renderAt: eng.renderAt, data: (load, act) => { life.setData({ load, act }); agentsOn = Math.round(act * 3); $("load").value = Math.round(load * 100); live(); }, event: (k, u, v, t) => life.event(k, u, v, t), pointer: (u, v, t) => life.setPointer(u, v, t), box, toEye };
eng.wake(capture ? 0 : 800);
document.body.classList.add("ready");

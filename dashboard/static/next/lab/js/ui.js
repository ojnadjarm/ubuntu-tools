/* UI-system lab page: living glyph background, glass-lens gauge, rolling counter with a sparkline trail, agent list with decode type, press ripples and a view-transition morph. */
import { background, gauge } from "./ui-gl.js";
import { KANA } from "./glyphs.js";

const still = matchMedia("(prefers-reduced-motion: reduce)");
const fine = matchMedia("(hover: hover)");
const $ = (id) => document.getElementById(id);
const BG = background($("bg")), LENS = gauge($("lens"));
const lensBox = $("lens");

const S = {
  t: 0, last: 0, raf: 0, until: 0, frames: 0, ms: [], scale: 1,
  par: [0, 0], parGoal: [0, 0], zoom: 1, zoomGoal: 1, pan: [0, 0], panGoal: [0, 0], scroll: 0,
  val: 0, valGoal: 0, press: 0, light: [-0.55, 0.65], lightGoal: [-0.55, 0.65],
  act: 0, actGoal: 0, load: 0, drift: 0, rip: new Float32Array(16), ri: 0, lensOn: true,
};
const decoding = new Set();

/* Frames only while something moves: ms keeps full rate after an input, then the loop stops; gl false ticks the DOM without redrawing the canvases. */
function wake(ms = 0, gl = true) {
  S.until = Math.max(S.until, performance.now() + ms);
  if (gl) S.dirty = true;
  if (!S.raf && !document.hidden) S.raf = requestAnimationFrame(loop);
}
function loop(now) {
  S.raf = 0;
  const dt = S.last ? Math.min(0.05, (now - S.last) / 1000) : 1 / 60;
  S.last = now;
  const busy = step(dt, now);
  for (const d of decoding) tickDecode(d, now);
  if (busy || S.dirty || now < S.until) { draw(); S.dirty = false; }
  if (!still.matches && !document.hidden && (busy || decoding.size || now < S.until)) { track(now); S.raf = requestAnimationFrame(loop); rate(now); }
  else { S.last = 0; S.ms = []; S.f0 = 0; $("fps").textContent = "idle · 0 fps"; }
}
function rate(now) {
  if (!S.f0) { S.f0 = now; S.n0 = S.frames; return; }
  if (now - S.f0 > 500) { $("fps").textContent = `${Math.round(((S.frames - S.n0) * 1000) / (now - S.f0))} fps`; S.f0 = now; S.n0 = S.frames; }
}
function track(now) {
  S.ms.push(now); if (S.ms.length > 40) S.ms.shift();
  if (S.ms.length < 40) return;
  if ((S.ms[39] - S.ms[0]) / 39 > 21 && S.scale > 0.45) { S.scale *= 0.85; S.ms = []; }
}

const near = (a, b) => Math.abs(a - b) < 1e-3;
function step(dt, now) {
  const k = (rate) => (still.matches ? 1 : 1 - Math.exp(-rate * dt));
  S.t += dt;
  S.drift += dt * (0.5 + 1.5 * S.load);
  const mv = (key, goal, rate) => { const v = S[key]; if (Array.isArray(v)) { v[0] += (goal[0] - v[0]) * k(rate); v[1] += (goal[1] - v[1]) * k(rate); } else S[key] = v + (goal - v) * k(rate); };
  mv("par", S.parGoal, 4); mv("pan", S.panGoal, 5); mv("zoom", S.zoomGoal, 5); mv("val", S.valGoal, 3.2); mv("light", S.lightGoal, 8); mv("act", S.actGoal, 3);
  S.press *= Math.exp(-6 * dt);
  let busy = !near(S.par[0], S.parGoal[0]) || !near(S.par[1], S.parGoal[1]) || !near(S.zoom, S.zoomGoal) || !near(S.pan[0], S.panGoal[0]) || !near(S.pan[1], S.panGoal[1])
    || !near(S.val, S.valGoal) || !near(S.light[0], S.lightGoal[0]) || !near(S.act, S.actGoal) || S.press > 0.01;
  for (let i = 0; i < 4; i++) if (S.rip[i * 4 + 3] > 0 && S.t - S.rip[i * 4 + 2] < 1.6) busy = true;
  return busy;
}

function draw() {
  const dpr = Math.min(devicePixelRatio || 1, 2), bs = Math.min(dpr, 1.5) * 0.75 * S.scale;
  BG.draw(Math.max(2, Math.round(innerWidth * bs)), Math.max(2, Math.round(innerHeight * bs)),
    { uTime: S.t, uDrift: S.drift, uAct: S.act, uPar: S.par, uPan: S.pan, uZoom: S.zoom, uScroll: S.scroll, uRip: S.rip });
  if (LENS && S.lensOn) {
    const r = lensBox.getBoundingClientRect();
    if (r.width > 0) LENS.draw(Math.round(r.width * dpr), Math.round(r.height * dpr), { uTime: S.t, uAct: S.act, uVal: S.val, uPress: S.press, uLight: S.light });
  }
  S.frames++;
}

/* Decode type: each character flickers through katakana, then settles left to right. */
function decode(el, text, delay = 0, loop = false) {
  decoding.forEach((d) => { if (d.el === el) decoding.delete(d); });
  if (still.matches && !loop) { el.textContent = text; return; }
  el.textContent = "";
  const sr = document.createElement("span"); sr.className = "sr-only"; sr.textContent = loop ? "loading" : text;
  const vis = document.createElement("span"); vis.className = "dec"; vis.setAttribute("aria-hidden", "true");
  const cells = [], t0 = performance.now() + delay, span = Math.min(900, 160 + text.length * 22);
  text.split(/( )/).forEach((w) => {
    if (w === " ") { vis.append(" "); return; }
    const wd = document.createElement("span"); wd.className = "wd";
    for (const ch of w) {
      const i = document.createElement("i"); i.className = "kx"; i.textContent = KANA[(Math.random() * KANA.length) | 0];
      wd.append(i); cells.push({ i, ch, at: t0 + (cells.length / Math.max(1, text.length - 1)) * span + Math.random() * 140 });
    }
    vis.append(wd);
  });
  el.append(sr, vis);
  const d = { el, text, cells, loop, swap: 0 };
  decoding.add(d);
  wake(0, false);
}
function tickDecode(d, now) {
  const flick = now - d.swap > 60;
  if (flick) d.swap = now;
  let left = 0;
  for (const c of d.cells) {
    if (c.done) continue;
    if (!d.loop && now >= c.at) { c.i.className = ""; c.i.textContent = c.ch; c.done = true; continue; }
    left++;
    if (flick && Math.random() < 0.6) c.i.textContent = KANA[(Math.random() * KANA.length) | 0];
  }
  if (!left && !d.loop) { d.el.textContent = d.text; decoding.delete(d); }
}

/* Rolling digits: each digit is a 0–9 strip moved by a transform; other characters are static. */
function roll(el, str) {
  if (el.dataset.s === str) return;
  const chars = [...str], kids = [...el.children];
  const same = kids.length === chars.length && chars.every((c, i) => /\d/.test(c) === kids[i].classList.contains("dg"));
  if (!same) {
    el.textContent = "";
    chars.forEach((c, i) => {
      const s = document.createElement("span");
      if (/\d/.test(c)) { s.className = "dg"; s.style.setProperty("--i", chars.length - i); const st = document.createElement("span"); st.className = "st"; st.textContent = "0123456789"; s.append(st); }
      else s.className = "sy";
      el.append(s);
    });
    el.offsetWidth;
  }
  chars.forEach((c, i) => { const s = el.children[i]; if (/\d/.test(c)) s.style.setProperty("--d", c); else s.textContent = c; });
  el.dataset.s = str;
}

/* Sparkline trail: a smooth path through the samples, a washed area under it and a glowing tip at the newest sample. */
function spark(vals) {
  const n = vals.length;
  if (n < 2) return;
  const top = Math.max(...vals) * 1.2 || 1;
  const P = vals.map((v, i) => [(i / (n - 1)) * 100, 31 - (v / top) * 28]);
  let d = `M${P[0][0].toFixed(2)} ${P[0][1].toFixed(2)}`;
  for (let i = 0; i < n - 1; i++) {
    const a = P[Math.max(0, i - 1)], b = P[i], c = P[i + 1], e = P[Math.min(n - 1, i + 2)];
    d += `C${(b[0] + (c[0] - a[0]) / 6).toFixed(2)} ${(b[1] + (c[1] - a[1]) / 6).toFixed(2)} ${(c[0] - (e[0] - b[0]) / 6).toFixed(2)} ${(c[1] - (e[1] - b[1]) / 6).toFixed(2)} ${c[0].toFixed(2)} ${c[1].toFixed(2)}`;
  }
  $("sp-l").setAttribute("d", d);
  $("sp-a").setAttribute("d", `${d}L100 32L0 32Z`);
  const tip = $("sp-h");
  tip.style.top = `${(P[n - 1][1] / 32) * 100}%`;
  tip.classList.remove("hit"); tip.offsetWidth; tip.classList.add("hit");
  $("cpu").classList.add("drawn");
}

const fmt = (v, dp = 1) => (v == null || !isFinite(v) ? "…" : v.toFixed(dp));
const ago = (sec) => (sec < 90 ? `${Math.max(1, Math.round(sec))} s` : sec < 5400 ? `${Math.round(sec / 60)} min` : sec < 172800 ? `${Math.round(sec / 3600)} h` : `${Math.round(sec / 86400)} d`);
const STATE = { working: "running", done: "idle", stale: "idle", error: "warn" };
let agents = [], cpu = null, ram = null, loading = false;

function live() {
  const on = agents.filter((a) => a.state === "working").length;
  $("live").textContent = `cpu ${fmt(cpu)} % · mem ${fmt(ram, 0)} % · ${on} agent${on === 1 ? "" : "s"} working`;
}

async function status() {
  const was = [$("cpu-v").dataset.s, $("ram-v").dataset.s];
  try {
    const s = await (await fetch("/api/status")).json();
    const c = s.sparks && s.sparks.cpu && s.sparks.cpu.values, m = s.sparks && s.sparks.ram && s.sparks.ram.values;
    if (c && c.length) {
      cpu = c[c.length - 1];
      roll($("cpu-v"), fmt(cpu));
      $("cpu-t").textContent = `${fmt(cpu)} percent`;
      $("cpu-s").textContent = `trail · last ${c.length} samples`;
      $("cpu-lo").textContent = `${fmt(Math.min(...c))} %`; $("cpu-me").textContent = `${fmt(c.reduce((a, b) => a + b, 0) / c.length)} %`; $("cpu-hi").textContent = `${fmt(Math.max(...c))} %`;
      if (c.join() !== status.c) { status.c = c.join(); spark(c); }
      S.load = Math.min(1, cpu / 40);
    }
    if (m && m.length) {
      ram = m[m.length - 1];
      roll($("ram-v"), fmt(ram, 0));
      $("ram-m").setAttribute("aria-valuenow", fmt(ram, 0));
      S.valGoal = ram / 100;
    }
  } catch { /* offline: keep the last values */ }
  live();
  if (was[1] !== $("ram-v").dataset.s) wake(0);
}

function skeleton() {
  const ul = $("rows");
  ul.setAttribute("aria-busy", "true");
  ul.textContent = "";
  for (let i = 0; i < 6; i++) {
    const li = document.createElement("li"); li.className = "sk";
    const nm = document.createElement("span"); nm.className = "nm";
    li.append(nm); ul.append(li);
    decode(nm, "x".repeat(14 + ((i * 7) % 11)), 0, true);
  }
}

function render(fresh) {
  const ul = $("rows"), seen = new Set([...ul.querySelectorAll("[data-id]")].map((b) => b.dataset.id));
  decoding.forEach((d) => { if (d.loop) decoding.delete(d); });
  ul.textContent = "";
  ul.setAttribute("aria-busy", "false");
  const now = Date.now() / 1000;
  const list = [...agents].sort((a, b) => (a.state === "working") - (b.state === "working") || Date.parse(a.started) - Date.parse(b.started)).reverse().slice(0, 8);
  list.forEach((a, n) => {
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button"; b.className = "row lit tap"; b.dataset.id = a.id;
    b.innerHTML = `<i class="sd ${a.state}"></i><span class="nm"></span><span class="ty"></span><span class="ag"></span>`;
    b.querySelector(".ty").textContent = `${a.type || "agent"} · ${a.state}`;
    b.querySelector(".ag").textContent = a.last ? ago(now - a.last) : "";
    const nm = b.querySelector(".nm");
    if (fresh || !seen.has(a.id)) decode(nm, a.label || a.id, n * 70); else nm.textContent = a.label || a.id;
    li.append(b); ul.append(li);
  });
  const on = agents.filter((a) => a.state === "working").length;
  $("ag-n").textContent = `${on} working · ${agents.length} total`;
  if (S.actGoal !== Math.min(1, on / 3)) { S.actGoal = Math.min(1, on / 3); wake(0); }
  live();
}
const sig = (l) => l.map((a) => a.id + a.state + a.label).join("|");

async function fetchAgents(show) {
  if (loading) return;
  loading = true;
  if (show) skeleton();
  const t0 = performance.now(), before = sig(agents);
  try {
    const a = await (await fetch("/api/agents")).json();
    agents = a.subagents || [];
  } catch { /* keep the last list */ }
  if (show) await new Promise((r) => setTimeout(r, Math.max(0, 900 - (performance.now() - t0))));
  loading = false;
  if (show || sig(agents) !== before) { render(show); return; }
  const now = Date.now() / 1000;
  $("rows").querySelectorAll("[data-id]").forEach((b) => { const a = agents.find((x) => x.id === b.dataset.id); if (a && a.last) b.querySelector(".ag").textContent = ago(now - a.last); });
}

/* Row → detail and back: a View Transitions morph with a camera dolly in the background; FLIP when the API is missing. */
function swapView(toDetail, row, fill) {
  const list = $("agents"), det = $("detail");
  const from = row.getBoundingClientRect(), cx = (from.left + from.width / 2 - innerWidth / 2) / innerHeight, cy = (innerHeight / 2 - (from.top + from.height / 2)) / innerHeight;
  S.zoomGoal = toDetail ? 1.28 : 1; S.panGoal = toDetail ? [cx * 0.6, cy * 0.6] : [0, 0];
  wake(900);
  const apply = () => { if (fill) fill(); list.hidden = toDetail; det.hidden = !toDetail; };
  const done = () => { if (toDetail) { $("dt-h").focus({ preventScroll: true }); } else { const r = $("rows").querySelector(`[data-id="${row.dataset.id}"]`); if (r) r.focus({ preventScroll: true }); } };
  if (document.startViewTransition && !still.matches) {
    const a = toDetail ? row : det;
    a.style.viewTransitionName = "sel";
    const vt = document.startViewTransition(() => {
      a.style.viewTransitionName = "";
      apply();
      const b = toDetail ? det : $("rows").querySelector(`[data-id="${row.dataset.id}"]`) || list;
      b.style.viewTransitionName = "sel";
      swapView.named = b;
    });
    vt.finished.finally(() => { if (swapView.named) swapView.named.style.viewTransitionName = ""; done(); });
  } else {
    apply();
    if (toDetail && !still.matches) {
      const to = det.getBoundingClientRect();
      det.animate([{ transformOrigin: "0 0", transform: `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width}, ${from.height / to.height})`, opacity: 0.3 },
        { transformOrigin: "0 0", transform: "none", opacity: 1 }], { duration: 480, easing: "cubic-bezier(.12,.9,.24,1)" });
    }
    done();
  }
}

function openAgent(row) {
  const a = agents.find((x) => x.id === row.dataset.id);
  if (!a) return;
  swapView.row = row;
  swapView(true, row, () => {
    const st = $("dt-st"); st.className = `pill ${STATE[a.state] || "idle"}`; st.textContent = a.state;
    decode($("dt-h"), a.label || a.id, 160);
    const kv = $("dt-kv"); kv.textContent = "";
    const now = Date.now() / 1000;
    [["type", a.type || "agent"], ["started", a.started ? new Date(a.started).toLocaleString() : "…"], ["last active", a.last ? `${ago(now - a.last)} ago` : "…"], ["doing", a.doing || "…"], ["id", a.id]].forEach(([k, v]) => {
      const div = document.createElement("div"), dt = document.createElement("dt"), dd = document.createElement("dd");
      dt.textContent = k; dd.textContent = v; div.append(dt, dd); kv.append(div);
    });
    $("dt-rep").textContent = a.report || "No report yet.";
  });
}
function closeAgent() { if (!$("detail").hidden) swapView(false, swapView.row || $("detail")); }

/* Press feedback: the element dips, a ring leaves the press point and a ripple runs through the glyph field. */
function press(e) {
  const el = e.target.closest(".tap");
  if (!el) return;
  const r = el.getBoundingClientRect();
  el.style.setProperty("--rx", `${e.clientX - r.left}px`); el.style.setProperty("--ry", `${e.clientY - r.top}px`);
  el.classList.remove("hit"); el.offsetWidth; el.classList.add("hit");
  if (still.matches) return;
  const i = S.ri++ % 4;
  S.rip.set([(e.clientX - innerWidth / 2) / innerHeight, (innerHeight / 2 - e.clientY) / innerHeight, S.t, 1], i * 4);
  if (el.id === "ram") S.press = 1;
  wake(300);
}

addEventListener("pointerdown", press, { passive: true });
addEventListener("pointermove", (e) => {
  if (fine.matches) {
    const el = e.target.closest && e.target.closest(".lit");
    if (el) { const b = el.getBoundingClientRect(); el.style.setProperty("--mx", `${e.clientX - b.left}px`); el.style.setProperty("--my", `${e.clientY - b.top}px`); }
  }
  if (still.matches) return;
  S.parGoal = [(e.clientX / innerWidth - 0.5) * 2, (0.5 - e.clientY / innerHeight) * 2];
  const r = lensBox.getBoundingClientRect(), R = r.width / 2 || 1;
  const lx = (e.clientX - r.left - R) / R, ly = (r.top + R - e.clientY) / R, m = Math.hypot(lx, ly);
  S.lightGoal = m > 3 ? [-0.55, 0.65] : [lx / Math.max(1, m), ly / Math.max(1, m)];
  wake(250);
}, { passive: true });
document.documentElement.addEventListener("pointerleave", () => { S.parGoal = [0, 0]; S.lightGoal = [-0.55, 0.65]; wake(200); });
addEventListener("scroll", () => { if (still.matches) return; S.scroll = scrollY / innerHeight; wake(120); }, { passive: true });
addEventListener("resize", () => wake(0));
document.addEventListener("visibilitychange", () => { if (document.hidden) { cancelAnimationFrame(S.raf); S.raf = 0; S.last = 0; } else { status(); wake(0); } });
still.addEventListener("change", () => wake(0));
new IntersectionObserver((es) => { S.lensOn = es[es.length - 1].isIntersecting; if (S.lensOn) wake(0); }).observe(lensBox);

$("rows").addEventListener("click", (e) => { const row = e.target.closest(".row"); if (row) openAgent(row); });
$("back").addEventListener("click", closeAgent);
$("reload").addEventListener("click", () => fetchAgents(true));
addEventListener("keydown", (e) => { if (e.key === "Escape") closeAgent(); });

decode($("hero-h"), $("hero-h").textContent, 150);
fetchAgents(true);
status();
setInterval(() => { if (!document.hidden) { status(); fetchAgents(false); } }, 30000);
window.__ui = { S, wake, frames: () => S.frames };

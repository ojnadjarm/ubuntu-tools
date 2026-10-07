/* /next boot: registry-driven chrome, the shared router and screens, the data ticks, the UI motion and the stage around the eye. */
import { esc, p2 } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, start, go, newKeys, markSeen } from "/static/js/core/router.js";
import { SECTIONS, SCREENS } from "./screens.js";
import { store } from "./store.js";
import * as shapes from "./shapes.js";
import { fitEye } from "./gl/cam.js";
import { decode, decodeAll } from "./ui/decode.js";
import { fresh, roll, draw } from "./ui/num.js";
import { sync } from "./ui/sync.js";
import { verdict } from "./verdict.js";
import { bindTouch } from "./ui/touch.js";

const M = {}, L = {}, S = {}, grid = document.getElementById("grid"), board = document.getElementById("board");
const byId = Object.fromEntries(SCREENS.map((s) => [s.id, s]));
const still = matchMedia("(prefers-reduced-motion: reduce)");
const WORKING = (A) => ((A || {}).subagents || []).filter((s) => s.state === "working").length;
let FAILED = false, lastKey = "", lastScreen = "", rendered = "", tTimer = 0, aTimer = 0;

const SKEL = `<div class="nxs skel" aria-busy="true"><p class="sr-only">loading</p>${[0, 1, 2, 3, 4, 5].map((i) => `<div class="sk" style="--w:${38 + ((i * 23) % 50)}%"><i></i></div>`).join("")}</div>`;
SCREENS.forEach((s) => {
  S[s.id] = () => {
    if (rendered !== s.id) { fresh(); rendered = s.id; }
    if (!M[s.id]) { load(s.id); return SKEL; }
    const body = M[s.id].render(grid, store.D);
    return M[s.id].own ? body : band(s) + body;
  };
});

/* Imports a screen module once, then re-renders it if it is still the active screen. */
function load(id) {
  if (!L[id]) L[id] = import(byId[id].load).then((m) => { M[id] = m; if (cur === id) { if (m.enter) m.enter(false); go(id, true); } });
  return L[id];
}
/* A section opens on its first screen; Voice reopens the one used last. */
const firstOf = (sec) => { let v = null; try { v = sec === "voice" && byId[localStorage.getItem("voiceSection")]; } catch (e) {} return v || SCREENS.find((s) => s.sec === sec); };
const subsOf = (sec) => SCREENS.filter((s) => s.sec === sec);

/* The hero band over a shared screen: the eye's perch, the decoded screen name and one summary line. */
function summary(id) {
  const D = store.D || {}, units = (D.units || []).filter((u) => u.group !== "desktop"), sites = D.sites || [];
  const n = (a, f) => a.filter(f).length;
  if (id === "services") return `${units.length} units · ${n(units, (u) => u.active === "failed")} failed · ${n(sites, (s) => s.state === "stray")} strays · ${(D.timers || []).length} timers`;
  if (id === "sites") return `${sites.length} sites · ${n(sites, (s) => s.state === "down")} down · ${n(sites, (s) => s.state === "stray")} strays`;
  if (id === "docs") return `${(D.plans || []).length} docs, newest first`;
  if (id === "files") return `${((D.drop || {}).files || []).length} files in the drop`;
  if (id === "notes") return "the notes vault · search, read, link";
  return "the design system · tokens and components";
}
function band(s) {
  return `<section class="band" aria-label="${esc(s.name)} summary"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt"><p class="kin" data-dec>${esc(s.name)}</p><p class="bsum">${esc(summary(s.id))}</p></div></section>`;
}

function keys() {
  const D = store.D, k = { eye: [], sites: [], services: [], files: [], docs: [], notes: [] };
  if (D) {
    (D.plans || []).forEach((p) => k.docs.push("plan:" + p.url + "@" + p.updated));
    ((D.drop || {}).files || []).forEach((f) => k.files.push("file:" + f.name + "@" + f.mtime));
    const down = (D.sites || []).filter((s) => s.state === "down").map((s) => s.name), strays = (D.sites || []).filter((s) => s.state === "stray").map((s) => s.port), failed = (D.units || []).filter((u) => u.active === "failed").map((u) => u.unit);
    if (down.length) k.sites.push("sites@" + down.join(","));
    if (strays.length) k.services.push("strays@" + strays.join(","));
    if (failed.length) k.services.push("failed@" + failed.join(","));
    k.eye.push(...verdict(D).keys);
  }
  if (M.notes) M.notes.keys(k);
  return k;
}
function readHash() {
  const h = location.hash.slice(1), i = h.indexOf("?"), id = i < 0 ? h : h.slice(0, i);
  if (i >= 0 && M[id] && M[id].read) M[id].read(h.slice(i + 1));
  if (id === "voice") return firstOf("voice").id;
  return S[id] ? id : "eye";
}
const hash = (to) => (M[to] && M[to].hash ? M[to].hash() : location.hash.indexOf("#" + to + "?") === 0 ? location.hash : "#" + to);
function enter(to, force) {
  const m = M[to];
  if (byId[to].sec === "voice") try { localStorage.setItem("voiceSection", to); } catch (e) {}
  if (m && m.enter) m.enter(force);
  const moved = lastScreen !== to;
  if (!force && lastScreen && moved) scrollTo(0, 0);
  chrome();
  motion();
  if (moved && M[to]) decodeAll(grid, "[data-dec], .cell > h2", 45);
  rescene();
}
/* After any render: odometers roll to their values, new trails draw. */
function motion() { roll(grid); draw(grid); }

/* Rail verdict and clock, dock and sub-tabs with badges rolled up from screen to section. */
function chrome() {
  const D = store.D, s = byId[cur] || byId.eye, k = newKeys(), A = store.A, v = verdict(D);
  const n = (id) => (k[id] || []).length, errs = ((A || {}).subagents || []).filter((x) => x.state === "error").length;
  const badge = (id) => (id === "agents" ? errs : n(id)), live = (id) => (id === "agents" ? WORKING(A) : 0);
  document.querySelectorAll(".dock .sec").forEach((a) => {
    const sec = a.dataset.sec, on = sec === s.sec, b = subsOf(sec).reduce((t, x) => t + badge(x.id), 0), w = subsOf(sec).reduce((t, x) => t + live(x.id), 0), f = firstOf(sec);
    a.classList.toggle("on", on); a.setAttribute("aria-current", on ? "true" : "false");
    a.href = "#" + f.id; a.dataset.nav = f.id;
    a.querySelector("i").textContent = b || w || "";
    a.querySelector("i").className = b ? "" : w ? "live" : "none";
    a.setAttribute("aria-label", a.dataset.name + (b ? ": " + b + " need you" : w ? ": " + w + " working" : ""));
  });
  const subs = document.getElementById("subs"), focus = subs.contains(document.activeElement) && document.activeElement.dataset.nav;
  subs.setAttribute("aria-label", s.sec + " screens");
  sync(subs, subsOf(s.sec).map((x) => { const b = badge(x.id), w = live(x.id);
    return `<a href="#${x.id}" data-nav="${x.id}" class="sub${x.id === cur ? " on" : ""}" aria-current="${x.id === cur ? "page" : "false"}">${x.name}${b ? `<i>${b}</i>` : w ? `<i class="live">${w}</i>` : ""}</a>`; }).join(""));
  if (focus) { const f = subs.querySelector(`[data-nav="${focus}"]`); if (f && f !== document.activeElement) f.focus(); }
  const vd = document.getElementById("vd"), txt = !D ? "…" : FAILED ? "stale · retrying" : v.text;
  vd.className = "vd" + (!D ? "" : FAILED || v.bad ? " bad" : "");
  if (vd.textContent !== txt && !vd.dataset.decoding) { vd.textContent = txt; if (D) decode(vd); }
  const brand = (D && D.brand) || "DarkSaddler", sp = brand.indexOf(" "), bel = document.getElementById("brand"), host = document.getElementById("host");
  const bh = sp < 0 ? esc(brand) : `<span>${esc(brand.slice(0, sp))}</span> <span>${esc(brand.slice(sp + 1))}</span>`;
  if (bel.innerHTML !== bh) bel.innerHTML = bh;
  if (D && D.host) host.textContent = D.host + " · live";
  document.title = s.name + " · " + brand;
  clock();
}
function clock() { const d = new Date(); document.getElementById("clk").textContent = p2(d.getHours()) + ":" + p2(d.getMinutes()); }

/* The glyph shape behind a shared screen, the eye perched on its band. */
function legacy(s) {
  const D = store.D, narrow = innerWidth < 820, C = shapes.C, shape = s.shape;
  let pts = [], key = "";
  if (shape === "rain") {
    const cols = (D.units || []).filter((u) => u.group !== "desktop").map((u) => ({ h: u.rss ? Math.max(0.1, Math.min(1, (Math.log10(u.rss) - 5) / 4)) : 0.2, c: u.active === "failed" ? C.gold : C.mint }))
      .concat((D.sites || []).filter((x) => x.state === "stray").map(() => ({ h: 0.6, c: C.vio })));
    key = JSON.stringify(cols); pts = shapes.rain(cols, { w: narrow ? 11 : 24 });
  } else if (shape === "stars") {
    const star = (x) => ({ bright: x.ms == null ? 0.5 : 1 - Math.min(1, x.ms / 800), c: x.state === "down" ? C.gold : x.state === "stray" ? C.vio : C.mint });
    const g = ["mine", "moodle", "metrics"].map((n) => (D.sites || []).filter((x) => x.group === n).map(star));
    g[2] = g[2].concat((D.sites || []).filter((x) => x.state === "stray").map(star));
    key = JSON.stringify(g.map((x) => x.map((y) => [y.c, Math.round(y.bright * 3)]))); pts = shapes.stars(g);
  } else if (shape === "sheets") {
    const n = s.id === "docs" ? (D.plans || []).length : ((D.drop || {}).files || []).length;
    key = String(n); pts = shapes.sheets(n, { cols: narrow ? 3 : 6 });
  } else if (shape === "wave") pts = shapes.wave();
  else pts = shapes.swatch();
  return { key, pts: [...shapes.dust(narrow ? 600 : 1500), ...pts], box: document.getElementById("gl"), span: narrow ? 12 : 24, tilt: 0.25,
    eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

/* Points the stage at the active screen: through the pupil on a screen change, a data morph and a pulse when the data moved, else fresh anchors only. */
function rescene() {
  const st = store.stage, s = byId[cur];
  if (!st || !store.D || !s) return;
  const m = M[cur];
  if (!m) return;
  shapes.reseed();
  const next = m.scene ? m.scene(store.D) : legacy(s);
  if (!next) return;
  const key = cur + "|" + next.key + "|" + (innerWidth < 820);
  if (cur !== lastScreen) st.show(next, { via: !!lastScreen });
  else if (key !== lastKey) { st.show(next, { data: true }); if (next.pulse !== false) st.pulse(next.pulse || "info"); }
  else st.show(next, { keep: true });
  lastKey = key; lastScreen = cur;
}
store.rescene = rescene;
store.life = life;

function refresh() {
  if (!cur) return;
  const m = M[cur];
  const shown = m && m.own && grid.dataset.live && grid.querySelector(":scope > .nxs:not(.skel)");
  if (shown && m.keep) { chrome(); rescene(); return; }
  if (shown) {
    const changed = sync(grid, m.render(grid, store.D), 1);
    motion();
    changed.forEach((el, i) => decode(el, i * 60));
    chrome(); rescene(); return;
  }
  go(cur, true);
}
function life() {
  const D = store.D, c = ((D && D.sparks && D.sparks.cpu) || {}).values || [], cpu = c.length ? c[c.length - 1] : 5;
  if (store.stage) store.stage.data({ load: Math.min(1, cpu / 40), act: Math.min(1, WORKING(store.A) / 3) });
}
function agents() {
  return getJSON("/api/agents").then((a) => { store.A = a; life(); }).catch(() => {});
}
/* Fast agents poll while the court or roster is on screen and someone works; otherwise agents ride the 30 s tick. */
function fast() {
  clearTimeout(aTimer);
  if (document.hidden || (cur !== "agents" && cur !== "roster") || !WORKING(store.A)) return;
  aTimer = setTimeout(() => agents().then(() => { refresh(); fast(); }), 5000);
}
/* The 30 s tick, aligned to the wall clock so the minute display is never late; nothing runs while hidden. */
function tick() {
  clearTimeout(tTimer);
  if (document.hidden) return;
  tTimer = setTimeout(tick, 30000 - (Date.now() % 30000) + 20);
  clock();
  return Promise.all([getJSON("/api/status"), agents()]).then(([d]) => { store.D = d; FAILED = false; life(); refresh(); boot3d(); fast(); })
    .catch((e) => { console.error(e); FAILED = true; if (store.D) chrome(); else grid.innerHTML = '<div class="empty">panel API not answering · retrying in 30 s</div>'; });
}
document.addEventListener("visibilitychange", () => { if (document.hidden) { clearTimeout(tTimer); clearTimeout(aTimer); } else tick(); });

/* WebGL after the first paint; without it the page stays whole on its static glow. */
let booting = null;
function boot3d() {
  if (booting) return;
  booting = new Promise((ok) => (window.requestIdleCallback || ((f) => setTimeout(f, 60)))(ok, { timeout: 700 }))
    .then(() => import("./stage.js"))
    .then((m) => { store.stage = m.createStage(document.getElementById("gl")); window.__stage = store.stage; document.body.classList.add("gl"); life(); rescene(); })
    .catch((e) => { console.error(e); document.body.classList.add("nogl"); });
}

/* A tap on the nav: one history entry per screen, so Back returns to where he was. */
function nav(id) {
  const s = byId[id];
  if (!s || id === cur) return;
  history.pushState(null, "", "#" + id);
  const run = () => go(id);
  if (document.startViewTransition && !still.matches) document.startViewTransition(run); else run();
}
document.addEventListener("click", (e) => {
  const a = e.target.closest("a[data-nav]");
  if (a && !e.metaKey && !e.ctrlKey && !e.shiftKey && e.button === 0) { e.preventDefault(); nav(a.dataset.nav); return; }
  const m = M[cur];
  if (m && m.click && m.click(e)) { chrome(); return; }
  if (e.target.id === "clear") { markSeen(Object.values(newKeys()).flat()); chrome(); return; }
  const ev = e.target.closest(".ev");
  if (ev) { ev.classList.toggle("open"); return; }
  if (e.target.closest("a[href='#']")) e.preventDefault();
});
document.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === "Escape" && (e.target.id === "fq" || e.target.id === "nq")) { e.preventDefault(); e.target.blur(); return; }
  if (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
  const m = M[cur];
  if (m && m.key && m.key(e)) return;
  const k = e.key, s = byId[cur], subs = subsOf(s.sec), i = subs.indexOf(s);
  if (k >= "1" && k <= String(SECTIONS.length)) { nav(firstOf(SECTIONS[+k - 1].id).id); e.preventDefault(); }
  else if (k === "ArrowRight" && i < subs.length - 1) { nav(subs[i + 1].id); e.preventDefault(); }
  else if (k === "ArrowLeft" && i > 0) { nav(subs[i - 1].id); e.preventDefault(); }
  else if (k === "Escape") nav("eye");
});
document.addEventListener("input", (e) => { const m = M[cur]; if (m && m.input) m.input(e); });
let tx = null, ty = 0;
board.addEventListener("touchstart", (e) => { const t = e.changedTouches[0]; tx = t.clientX; ty = t.clientY; }, { passive: true });
board.addEventListener("touchend", (e) => {
  if (tx === null) return;
  const t = e.changedTouches[0], dx = t.clientX - tx, dy = t.clientY - ty;
  tx = null;
  if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5 || e.target.closest(".tw, .facets, .lb, .scape, .vx:not([data-rs=idle])")) return;
  const subs = subsOf(byId[cur].sec), i = subs.indexOf(byId[cur]) + (dx < 0 ? 1 : -1);
  if (i >= 0 && i < subs.length) nav(subs[i].id);
}, { passive: true });
addEventListener("pointermove", (e) => { const m = M[cur]; if (m && m.pointer) m.pointer(e); }, { passive: true });
addEventListener("scroll", () => { if (store.stage) store.stage.scroll(); }, { passive: true });
let rz = 0;
addEventListener("resize", () => { cancelAnimationFrame(rz); rz = requestAnimationFrame(() => rescene()); });
bindTouch();

document.querySelector(".dock").innerHTML = SECTIONS.map((s, i) =>
  `<a class="sec" href="#${firstOf(s.id).id}" data-nav="${firstOf(s.id).id}" data-sec="${s.id}" data-name="${s.name}"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true">${s.icon}</svg><span>${s.name}</span><i class="none"></i><kbd>${i + 1}</kbd></a>`).join("");
const first = readHash();
load(first);
start({ screens: S, ready: () => !!store.D, keys, read: readHash, enter, hash });
addEventListener("hashchange", () => { const id = readHash(); if (id !== cur) go(id); });
go(first);
tick();

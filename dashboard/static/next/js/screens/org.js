/* Office: the composition root of #org. Reads GET /api/office, builds the model and its plan, hands them to the 3D renderer and to the overlay (the keyboard list and the card a click opens). */
import { esc } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import { watch, talking } from "../familiars/talk.js";
import { listen } from "../familiars/ear.js";
import { sync } from "../ui/sync.js";
import { dust } from "../shapes.js";
import { fitEye } from "../gl/cam.js";
import { plural } from "../summary.js";
import { store } from "../store.js";
import { verdict } from "../verdict.js";
import { build, diff } from "../office/model.js";
import { plan as planOf } from "../office/layout.js";
import { until } from "../office/time.js";
import { list } from "../office/overlay/list.js";
import * as card from "../office/overlay/card.js";

export { seatState, titled, dmOf } from "../seats.js";
export const own = true, keep = true;
const STALE_MS = 20000, FAST_MS = 4500, DRAG_PX = 6;
const NOTE = "Still picture: this browser has no graphics acceleration. The list below is live.";
const grid = document.getElementById("grid"), canvas = document.createElement("canvas");
canvas.setAttribute("aria-hidden", "true");
let P = null, M = null, plan = null, applied = null, R = null, starting = false, at = 0, busy = false, err = "", down = null, over = null;

for (const href of ["/static/css/org.css", "/static/css/office.css"]) if (!document.querySelector(`link[href="${href}"]`)) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = href;
  document.head.appendChild(l);
}

const root = () => grid.querySelector(":scope > .nxs.office");

/* Builds the model and its plan from the last read: the CEO's lamp from the store, the seats that talk now. */
function model() {
  M = build(P, { needs: verdict(store.D).bad, talk: talking }); plan = planOf(M);
}

/* Reads /api/office when the copy is missing or older than max ms; never while the tab is hidden. */
function pull(max) {
  if (busy || document.hidden || (at && Date.now() - at < max)) return;
  busy = true;
  getJSON("/api/office").then((j) => { P = j; model(); err = M.error; }, (e) => { err = e.message || "unreadable"; })
    .finally(() => { busy = false; at = Date.now(); paint(); });
}

/* Rebuilds the model from the last read when the store's needs-you verdict no longer matches the CEO's lamp. */
function relamp() {
  if (!P || !M || !M.ceo || (M.ceo.live.lamp === "needs") === verdict(store.D).bad) return;
  model();
  paint();
}

/* The band's text: sessions, staff on, the next run, a stale note. */
function line() {
  const l = M.line;
  return `<p class="kin" data-dec>Office</p><p class="bsum"><b>${plural(l.sessions, "Claude session")} on this laptop</b>, ${l.working} working · ${l.on} of ${l.of} staff on` +
    `${l.soon ? ` · next up ${esc(l.soon.name)} in ${esc(until(l.soon.next))}` : ""}${err ? ` · stale: ${esc(err)}` : ""}</p>`;
}

/* Hands the renderer what changed since its last model; redraw forces a frame after the canvas came back. */
function show(redraw) {
  if (!R || !M || !canvas.isConnected) return;
  const patch = applied !== M ? diff(applied, M) : redraw ? { rooms: [(M.ceo || M.rooms[0]).id] } : null;
  if (patch) R.apply(M, plan, patch);
  applied = M;
}

/* The creature or sign under a pointer event on the canvas, or null. */
function under(e) {
  const r = canvas.getBoundingClientRect(), id = R.pick(e.clientX - r.left, e.clientY - r.top);
  return id && M && M.who[id] ? id : null;
}

/* Loads the furniture kit, the theme and the renderer once, then draws the office. */
function start(st) {
  if (starting) return;
  starting = true;
  Promise.all([import("../office/gl/index.js"), import("../office/theme.js"), import("../office/kit.js").then((k) => k.load())]).then(([gl, th, kit]) => {
    R = window.__office = gl.createRenderer(canvas, { theme: th.THEME, kit });
    canvas.addEventListener("pointerdown", (e) => { down = [e.clientX, e.clientY]; });
    canvas.addEventListener("click", (e) => {
      const id = down && Math.hypot(e.clientX - down[0], e.clientY - down[1]) < DRAG_PX && under(e);
      if (id) card.open(id, { x: e.clientX, y: e.clientY });
    });
    canvas.addEventListener("pointermove", (e) => {
      const id = e.pointerType === "mouse" && !e.buttons ? under(e) : null;
      if (id === over) return;
      over = id; R.hover(id);
      canvas.classList.toggle("hot", !!id);
    });
    canvas.addEventListener("pointerleave", () => { if (over) { over = null; R.hover(null); canvas.classList.remove("hot"); } });
    mount();
  }).catch((e) => { console.error(e); st.dataset.still = "1"; });
}

/* Puts the one canvas back into the stage of the fresh markup. */
function mount() {
  const st = document.querySelector(".office .stage");
  if (!st) return;
  const back = canvas.parentNode !== st;
  if (back) st.prepend(canvas);
  if (!R) { start(st); return; }
  st.dataset.still = R.still ? "1" : "";
  show(back);
}

/* After a read: the first answer renders the screen, later ones patch band and list in place and update card and scene. */
function paint() {
  if (cur !== "org") return;
  const el = root();
  if (!M || !el) { go("org", true); return; }
  sync(el.querySelector(".bt"), line());
  sync(el.querySelector(".olist"), list(M));
  card.refresh(M);
  show(false);
}

/* A seat starts or stops talking: the model takes its pose, then list, card and scene follow. */
watch(() => { if (cur === "org" && P && root()) { model(); paint(); } });

export function render() {
  pull(STALE_MS);
  listen(() => cur === "org");
  if (!M) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">${err ? "org unreadable · " + esc(err) : "reading the org…"}</p></div>`;
  card.refresh(M);
  queueMicrotask(mount);
  return `<div class="nxs org office"><section class="band" aria-label="Office summary"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt">${line()}</div></section>` +
    `<section class="stage" aria-label="The office"><div class="hud"><button type="button" id="office-zin" aria-label="Zoom in">+</button><button type="button" id="office-zout" aria-label="Zoom out">−</button><button type="button" id="office-reset">Reset view</button></div>` +
    `<p class="hint">Drag to turn · wheel or pinch to zoom · tap a creature or a room's sign</p><p class="still">${NOTE}</p></section>` +
    `<div class="olist">${list(M)}</div></div>`;
}

/* The dashboard's tick: the lamp follows the store at once, a fresh read every 20 s, every 5 s while someone works. */
export function tick() {
  relamp();
  pull(M && (M.line.working || M.panels.running.length) ? FAST_MS : STALE_MS);
}

/* A list button or a chip opens its card, the card's × closes it; the stage buttons move the camera. */
export function click(e) {
  const t = e.target.closest && e.target.closest("[data-who], [data-close], #office-zin, #office-zout, #office-reset");
  if (!t) return false;
  if ("close" in t.dataset) card.close();
  else if (t.dataset.who) { const r = t.getBoundingClientRect(); card.open(t.dataset.who, t.closest("#office-card") ? null : { x: r.left + r.width / 2, y: r.bottom }); }
  else if (R) t.id === "office-reset" ? R.reset() : R.zoom(t.id === "office-zin" ? 0.8 : 1.25);
  return true;
}

/* Escape closes an open card instead of leaving the screen. */
export function key(e) {
  if (e.key !== "Escape" || !card.isOpen()) return false;
  card.close();
  return true;
}

/* The eye on the band's perch over a field of dust, as on the shared screens. */
export function scene() {
  const narrow = innerWidth < 820;
  return { key: "org", pts: dust(narrow ? 600 : 1500), box: document.getElementById("gl"), span: narrow ? 12 : 24, tilt: 0.25,
    eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

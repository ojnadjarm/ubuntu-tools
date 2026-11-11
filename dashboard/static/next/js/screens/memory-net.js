/* Library › Memory › Network: the recall network as a sky (memories as stars by domain, concepts between them, last night's learned links in gold) and a "try a prompt" box that lights the path. GET /api/memory/net, GET /api/memory/net/try?q=; PRIVATE pages by name only. */
import { esc } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";

const STALE_MS = 60000, GA = Math.PI * (3 - Math.sqrt(5)), FILL = 0.22;
const TOKENS = ["--g", "--gold", "--vio2", "--g2", "--hi", "--vio", "--mid"];
let NET = null, at = 0, err = "", Q = "", TRY = null, busy = false, ver = 0, drawn = -1, repaint = () => {};
const canvas = document.createElement("canvas");
canvas.setAttribute("role", "img");

if (!document.querySelector('link[href="/static/css/memory-net.css"]')) { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "/static/css/memory-net.css"; document.head.appendChild(l); }

/* fn repaints the Memory screen; called after every read. */
export function bind(fn) { repaint = fn; }

/* Reads the network when missing or older than STALE_MS; no timer. */
export function enter() {
  if (NET && Date.now() - at < STALE_MS) return;
  at = Date.now();
  getJSON("/api/memory/net").then((j) => { NET = j; err = ""; ver++; }, (e) => { err = e.message; }).then(repaint);
}

/* Domains in drawing order (core first, then by size), each with its places and a colour token. */
function domains(net) {
  const D = new Map();
  for (const p of net.places) { const d = D.get(p.domain) || { name: p.domain, n: 0, places: [], priv: [] }; (p.private ? d.priv : d.places).push(p.place); d.n += p.private ? 1 : p.n; D.set(p.domain, d); }
  const out = [...D.values()].sort((a, b) => (b.name === "core") - (a.name === "core") || b.n - a.n || (a.name < b.name ? -1 : 1));
  out.forEach((d, i) => { d.tok = TOKENS[i % TOKENS.length]; });
  return out;
}

/* Pushes overlapping domain discs (radius plus a label line) apart, each kept inside the box. */
function apart(doms, w, h, pad) {
  for (let it = 0; it < 300; it++) {
    let moved = false;
    for (let i = 0; i < doms.length; i++) for (let j = i + 1; j < doms.length; j++) {
      const a = doms[i], b = doms[j], dx = b.x - a.x || 0.01, dy = b.y - a.y, d = Math.hypot(dx, dy), need = a.r + b.r + 18;
      if (d >= need) continue;
      const k = (need - d) / d / 2;
      a.x -= dx * k; a.y -= dy * k; b.x += dx * k; b.y += dy * k; moved = true;
    }
    for (const d of doms) { d.x = Math.min(Math.max(d.x, pad + d.r), w - pad - d.r); d.y = Math.min(Math.max(d.y, pad + d.r + 14), h - pad - d.r); }
    if (!moved) return;
  }
}

/* Pixel positions for a w x h box: domain centres on a golden-angle spiral (biggest in the middle), its memories on a spiral round it, a concept at the mean of its memories. */
function layout(net, w, h) {
  const doms = domains(net), byPlace = new Map(), star = new Map(), pad = Math.min(w, h) * 0.04;
  doms.forEach((d) => d.places.forEach((p) => byPlace.set(p, d)));
  const mems = net.memories.filter((m) => byPlace.has(m[1])).sort((a, b) => (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : a[0] < b[0] ? -1 : 1));
  const s = Math.sqrt((FILL * w * h) / (Math.PI * Math.max(1, mems.length + doms.length)));
  const lo = Math.min(...mems.map((m) => m[2]), 0), hi = Math.max(...mems.map((m) => m[2]), lo + 1e-6);
  doms.forEach((d, i) => {
    d.r = s * Math.sqrt(Math.max(1, d.n));
    const k = Math.sqrt((i + 0.5) / doms.length) * (doms.length > 1 ? 1 : 0), a = i * GA;
    d.x = w / 2 + k * Math.cos(a) * Math.max(0, w / 2 - pad - d.r);
    d.y = h / 2 + k * Math.sin(a) * Math.max(0, h / 2 - pad - d.r - 12);
  });
  apart(doms, w, h, pad);
  doms.forEach((d, i) => {
    const own = mems.filter((m) => byPlace.get(m[1]) === d);
    own.forEach((m, j) => {
      const r = d.r * Math.sqrt((j + 0.5) / own.length), t = j * GA + i;
      star.set(m[0], { id: m[0], place: m[1], x: d.x + r * Math.cos(t), y: d.y + r * Math.sin(t), size: 1.2 + 2.6 * (m[2] - lo) / (hi - lo), tok: d.tok });
    });
  });
  const tied = new Map();
  for (const [a, b] of net.links) if (a.startsWith("c:") && b.startsWith("m:") && star.has(b.slice(2))) { if (!tied.has(a)) tied.set(a, []); tied.get(a).push(star.get(b.slice(2))); }
  const concept = new Map();
  for (const [c, ss] of tied) concept.set(c, { x: ss.reduce((t, q) => t + q.x, 0) / ss.length, y: ss.reduce((t, q) => t + q.y, 0) / ss.length, n: ss.length });
  return { doms, star, concept, tied };
}

const css = (t) => getComputedStyle(document.documentElement).getPropertyValue(t).trim() || "#888";

/* Draws the sky, then the tried prompt's path on top: its cue concepts, the lines to the memories they fired, the fired stars. */
function draw() {
  const w = canvas.clientWidth, h = canvas.clientHeight, dpr = devicePixelRatio || 1;
  if (!NET || !w || !h) return;
  canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
  const g = canvas.getContext("2d"), L = layout(NET, w, h), col = {};
  for (const t of TOKENS.concat(["--line3", "--mute", "--bg", "--gold", "--hi"])) col[t] = css(t);
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, h);
  g.globalAlpha = 0.16; g.strokeStyle = col["--line3"];
  for (const [a, b, wt] of NET.links) {
    const c = L.concept.get(a), m = b.startsWith("m:") && L.star.get(b.slice(2));
    if (!c || !m || c.n < 2) continue;
    g.lineWidth = Math.min(2, 0.2 + 0.12 * wt); g.beginPath(); g.moveTo(c.x, c.y); g.lineTo(m.x, m.y); g.stroke();
  }
  g.globalAlpha = 0.9; g.strokeStyle = col["--gold"]; g.lineWidth = 1.2;
  for (const [a, b] of NET.fresh || []) {
    const p = a.startsWith("c:") ? L.concept.get(a) : L.star.get(a.slice(2)), q = L.star.get(b.slice(2));
    if (p && q) { g.beginPath(); g.moveTo(p.x, p.y); g.lineTo(q.x, q.y); g.stroke(); }
  }
  g.globalAlpha = 1;
  for (const s of L.star.values()) { g.fillStyle = col[s.tok]; g.beginPath(); g.arc(s.x, s.y, s.size, 0, 7); g.fill(); }
  g.font = `${Math.max(10, Math.min(13, w / 90))}px ui-monospace, monospace`; g.textAlign = "center";
  for (const d of L.doms) {
    if (!d.places.length) { g.strokeStyle = col["--mute"]; g.setLineDash([3, 3]); g.beginPath(); g.arc(d.x, d.y, Math.max(6, d.r), 0, 7); g.stroke(); g.setLineDash([]); }
    const name = d.name + (d.places.length ? "" : " · private"), half = g.measureText(name).width / 2 + 2;
    g.fillStyle = col["--mute"]; g.fillText(name, Math.min(Math.max(d.x, half), w - half), Math.max(12, d.y - d.r - 5));
  }
  const lit = [];
  if (TRY && TRY.hints.length) {
    g.globalAlpha = 0.6; g.fillStyle = col["--bg"]; g.fillRect(0, 0, w, h); g.globalAlpha = 1;
    for (const f of TRY.hints) {
      const m = L.star.get(f.id);
      if (!m) continue;
      lit.push(f.id);
      const why = f.why || [];
      why.forEach((label, k) => {
        const word = label.replace(/^~/, "").split(">")[0], far = L.concept.get("c:" + word), t = (k / why.length) * 2 * Math.PI - Math.PI / 2;
        if (!far) return;
        const c = Math.hypot(far.x - m.x, far.y - m.y) > 40 ? far : { x: m.x + 46 * Math.cos(t), y: m.y + 46 * Math.sin(t) };
        g.strokeStyle = col["--gold"]; g.lineWidth = 1.5; g.beginPath(); g.moveTo(c.x, c.y); g.lineTo(m.x, m.y); g.stroke();
        g.fillStyle = col["--gold"]; g.beginPath(); g.arc(c.x, c.y, 2.5, 0, 7); g.fill();
        g.fillText(word, c.x, c.y - 6);
      });
      g.fillStyle = col[m.tok]; g.beginPath(); g.arc(m.x, m.y, m.size + 2, 0, 7); g.fill();
      g.strokeStyle = col["--hi"]; g.lineWidth = 1.5; g.beginPath(); g.arc(m.x, m.y, m.size + 6, 0, 7); g.stroke();
      g.fillStyle = col["--hi"]; g.textAlign = "left"; g.fillText("^" + f.id, m.x + m.size + 9, m.y + 4); g.textAlign = "center";
    }
  }
  canvas.dataset.stars = String(L.star.size);
  canvas.dataset.lit = lit.join(" ");
  canvas.setAttribute("aria-label", `recall network: ${L.star.size} memories in ${L.doms.length} domains` + (lit.length ? `; lit: ${lit.map((x) => "^" + x).join(", ")}` : ""));
  canvas._layout = L;
}

let seen = "";
new ResizeObserver(() => { const k = canvas.clientWidth + "x" + canvas.clientHeight; if (k !== seen) { seen = k; draw(); } }).observe(canvas);

/* A click on a star opens its page in the Pages view. */
canvas.addEventListener("click", (e) => {
  const L = canvas._layout, r = canvas.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
  if (!L) return;
  let best = null, dist = 14 * 14;
  for (const s of L.star.values()) { const d = (s.x - x) ** 2 + (s.y - y) ** 2; if (d < dist) { dist = d; best = s; } }
  if (best) location.hash = "#memory?p=" + encodeURIComponent(best.place);
});

/* Puts the one canvas back into the fresh markup and draws when it came back or the data changed. */
function mount() {
  const box = document.getElementById("mnsky");
  if (!box) return;
  if (canvas.parentNode !== box) box.prepend(canvas);
  if (drawn !== ver || !canvas.width) { drawn = ver; draw(); }
}

export function input(e) { if (e.target.id === "mnq") Q = e.target.value; }

document.addEventListener("submit", (e) => {
  if (!e.target.matches("form.mnform")) return;
  e.preventDefault();
  const q = e.target.querySelector("input").value.trim();
  if (!q || busy) return;
  Q = q; busy = true; repaint();
  getJSON("/api/memory/net/try?q=" + encodeURIComponent(q)).then((j) => { TRY = j; }, (er) => { TRY = { error: er.message, hints: [] }; })
    .then(() => { busy = false; ver++; repaint(); });
});

function result() {
  if (busy) return `<p class="sm">firing…</p>`;
  if (!TRY) return `<p class="sm">Type what you would say to an agent. The network fires as your own session would: at most 3 hints, or silence.</p>`;
  if (TRY.error) return `<p class="sm bad">${esc(TRY.error)}</p>`;
  if (TRY.off) return `<p class="sm bad">Recall is off (MEMORY_RECALL=off).</p>`;
  const cues = `<p class="mncues"><b>cues</b> ${TRY.cues.length ? TRY.cues.map((c) => `<code>${esc(c.slice(2))}</code>`).join(" ") : "none"}</p>`;
  if (!TRY.hints.length) return cues + `<p class="sm">Silence: nothing crossed its threshold. The agent gets 0 bytes.</p>`;
  const li = (f) => `<li data-id="${esc(f.id)}"><b>^${esc(f.id)}</b><span class="pl">${esc(f.place)}</span>` +
    `<span class="why">${f.why ? esc(f.why.join(" | ")) : "private · id and place only"}</span><s>${esc(String(f.activation))}</s></li>`;
  return cues + `<ol class="mnhints">${TRY.hints.map(li).join("")}</ol><p class="mnlbl">what the agent sees</p><pre class="mnblock">${esc(TRY.block)}</pre>`;
}

function key(doms) {
  const n = (d) => (d.places.length ? d.n - d.priv.length : "") + (d.priv.length ? `${d.places.length ? " + " : ""}${d.priv.length} private` : "");
  return `<section class="pane mnkeys" aria-label="domains"><h2>domains<s>${doms.length}</s></h2><ul class="mnkey">` +
    doms.map((d) => `<li style="--c: var(${d.tok})"><i></i>${esc(d.name)}<s>${n(d)}</s></li>`).join("") + `</ul></section>`;
}

export function render() {
  queueMicrotask(mount);
  const st = NET && NET.stats, sum = st ? `${st.memories} memories · ${st.concepts} concepts · ${st.links} links` : err ? esc(err) : "reading…";
  return `<div class="mngrid"><section class="pane mnet" aria-label="recall network"><h2>network<s>${sum}</s></h2>` +
    `<p class="mnhow">Stars are memories, coloured by domain, bigger when his word is newer; faint lines tie a concept to its memories, wider when stronger; gold lines were learned last night. Click a star to read its page. Private pages are counted, never drawn.</p>` +
    `<div class="mnsky" id="mnsky"></div></section>` +
    `<div class="mnside"><section class="pane mntry" aria-label="try a prompt"><h2>try a prompt<s>as your own session</s></h2>` +
    `<form class="mnform" role="search"><input id="mnq" name="q" type="search" maxlength="2000" autocomplete="off" placeholder="type a prompt…" aria-label="prompt" value="${esc(Q)}"><button class="btn" type="submit">fire</button></form>` +
    `<div class="mnout" aria-live="polite">${result()}</div></section>${NET ? key(domains(NET)) : ""}</div></div>`;
}

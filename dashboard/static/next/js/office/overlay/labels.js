/* Tags pinned to world points of the office: one per room, a small one per worker at a desk; a tap opens the card. */
import { esc } from "/static/js/core/fmt.js";
import { SLOTS } from "../model.js";

const NEAR_PX = 160, GAP = 3, TRIES = 12;
const KIND = { ceo: 0, seat: 1, pool: 2, team: 3 };
const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");
const busy = (pose) => pose === "working" || pose === "talking";
const tag = (id, cls, rank, html) => `<button type="button" class="otag ${cls}" data-who="${esc(id)}" data-rank="${rank}" tabindex="-1">${html}</button>`;

/* The tags of one room: its own, then its workers'; rank orders who gets its spot first (working rooms, then by kind, workers last). */
function room(r) {
  const crew = r.kind === "seat" ? r.people.slice(1) : r.kind === "pool" ? r.people : [], n = crew.length;
  const small = r.kind === "team" ? `${r.people.length} staff · ${r.busy} running` : r.kind === "pool" ? plural(n, "agent") + (r.more ? ` · +${r.more}` : "")
    : r.kind === "seat" ? [r.area, n ? plural(n, "worker") + (r.more ? ` · +${r.more}` : "") : ""].filter(Boolean).join(" · ") : "";
  return tag(r.id, r.pose + " k-" + r.kind, (busy(r.pose) ? 0 : 4) + KIND[r.kind], `<i></i><b>${esc(r.name)}</b><span>${esc(r.rank)}</span><small>${esc(small)}</small>`) +
    crew.slice(0, SLOTS).map((p) => tag(p.id, p.pose + " mini", busy(p.pose) ? 8 : 9, `<i></i><b>${esc(p.name)}</b>`)).join("");
}

/* The top edge for a w × h tag over point (x, y) that overlaps none of `taken`: its own spot, the last lift, else stacked above, else below the tags in its way; null when none fits. */
function spot(taken, x, y, w, h, H, last) {
  const hit = (t) => taken.find((o) => x - w / 2 < o.r && x + w / 2 > o.l && t < o.b && t + h > o.t);
  const ok = (t) => t >= 0 && t + h <= H && !hit(t);
  if (ok(y - h)) return y - h;
  if (last != null && ok(y - h - last)) return y - h - last;
  for (const dir of [-1, 1]) {
    let t = Math.max(0, Math.min(H - h, y - h));
    for (let k = 0; k < TRIES; k++) {
      const o = hit(t);
      if (!o) { if (ok(t)) return t; break; }
      t = dir < 0 ? o.t - GAP - h : o.b + GAP;
      if (t < 0 || t + h > H) break;
    }
  }
  return null;
}

/* labels(host, renderer) → {update(M), place()}: update redraws the tags (worker tags show once the CEO and the desk pool are NEAR_PX apart, a close view), place moves them to their projected points, whole inside the stage, no two overlapping: a moved tag draws a leader line to its point. */
export function labels(host, R) {
  let html = "", ends = [];
  const lift = new Map();
  function place() {
    const a = ends.map((id) => R.project(id));
    host.classList.toggle("near", a.length === 2 && Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y) > NEAR_PX);
    const els = [...host.children], q = els.map((el) => R.project(el.dataset.who));
    els.forEach((el, i) => { el.hidden = !q[i].ok; });
    const W = host.clientWidth, H = host.clientHeight, taken = [];
    const at = els.map((el, i) => { const r = el.getBoundingClientRect(); return { el, q: q[i], w: r.width, h: r.height, rank: +el.dataset.rank }; })
      .filter((t) => t.q.ok && t.w).sort((m, n) => m.rank - n.rank);
    for (const { el, q: p, w, h } of at) {
      const id = el.dataset.who, x = Math.max(w / 2, Math.min(W - w / 2, p.x)), top = spot(taken, x, p.y, w, h, H, lift.get(id));
      if (top == null) { el.hidden = true; lift.delete(id); continue; }
      const up = p.y - h - top;
      taken.push({ l: x - w / 2, r: x + w / 2, t: top, b: top + h });
      el.classList.toggle("led", Math.abs(up) > 2);
      el.classList.toggle("dn", up < -2);
      el.style.setProperty("--lead", Math.abs(up) > 2 ? Math.round(up) + "px" : "0");
      if (Math.abs(up) > 2) lift.set(id, up); else lift.delete(id);
      el.style.transform = `translate(${(x - w / 2).toFixed(1)}px,${top.toFixed(1)}px)`;
    }
  }
  function update(M) {
    const next = [M.ceo, ...M.rooms, ...M.staff].filter(Boolean).map(room).join("");
    if (next !== html) host.innerHTML = html = next;
    ends = M.ceo ? [M.ceo.id, "pool"] : [];
    place();
  }
  return { update, place };
}

/* Tags pinned to world points of the office: one per room, a small one per worker at a desk; a tap opens the card. */
import { esc } from "/static/js/core/fmt.js";
import { SLOTS } from "../model.js";

const NEAR_PX = 160;
const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");
const tag = (id, cls, html) => `<button type="button" class="otag ${cls}" data-who="${esc(id)}" tabindex="-1">${html}</button>`;

/* The tags of one room: its own, then its workers'. */
function room(r) {
  const crew = r.kind === "seat" ? r.people.slice(1) : r.kind === "pool" ? r.people : [], n = crew.length;
  const small = r.kind === "team" ? `${r.people.length} staff · ${r.busy} running` : r.kind === "pool" ? plural(n, "agent") + (r.more ? ` · +${r.more}` : "")
    : r.kind === "seat" ? [r.area, n ? plural(n, "worker") + (r.more ? ` · +${r.more}` : "") : ""].filter(Boolean).join(" · ") : "";
  return tag(r.id, r.pose + " k-" + r.kind, `<i></i><b>${esc(r.name)}</b><span>${esc(r.rank)}</span><small>${esc(small)}</small>`) +
    crew.slice(0, SLOTS).map((p) => tag(p.id, p.pose + " mini", `<i></i><b>${esc(p.name)}</b>`)).join("");
}

/* labels(host, renderer) → {update(M), place()}: update redraws the tags (worker tags show once the CEO and the desk pool are NEAR_PX apart, a close view), place moves them to their projected points, whole inside the stage. */
export function labels(host, R) {
  let html = "", ends = [];
  function place() {
    const a = ends.map((id) => R.project(id));
    host.classList.toggle("near", a.length === 2 && Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y) > NEAR_PX);
    const W = host.clientWidth, at = [...host.children].map((el) => [el, R.project(el.dataset.who), el.offsetWidth / 2]);
    for (const [el, q, half] of at) {
      el.hidden = !q.ok;
      if (q.ok) el.style.transform = `translate(${Math.max(half, Math.min(W - half, q.x)).toFixed(1)}px,${q.y.toFixed(1)}px) translate(-50%,-100%)`;
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

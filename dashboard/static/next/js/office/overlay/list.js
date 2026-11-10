/* Staff list: the office as plain text. The seat tree (a card per seat, its workers under it) and the staff teams; every name is a button that opens its card. */
import { esc } from "/static/js/core/fmt.js";
import { familiar } from "../../familiars/alive.js";
import { titled, dmOf } from "../../seats.js";
import { plural } from "../../summary.js";

const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const PILL = { working: "running", running: "running", idle: "idle", asleep: "off", off: "off", yours: "his", error: "failed" };
const SHOWN = 3;
const BUBBLE = '<svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v11H10l-5 4v-4H4z"/></svg>';

const dot = (st) => `<span class="pill dot ${PILL[st] || "idle"}" title="${esc(st)}"><span class="sr-only">${esc(st)}</span></span>`;
const who = (id, html) => `<button type="button" class="who" data-who="${esc(id)}">${html}</button>`;

/* An avatar button described by its tooltip (a top-layer popover): lines[0] bold, the rest plain; hover, keyboard focus or a tap shows it. */
const av = (id, name, art, lines) => `<span class="av"><button type="button" class="avb" aria-label="About ${esc(name)}" aria-describedby="tip-${esc(id)}">${art}</button>` +
  `<span class="tip" role="tooltip" popover="manual" id="tip-${esc(id)}">${lines.filter(Boolean).map((l, i) => (i ? `<span>${esc(l)}</span>` : `<b>${esc(l)}</b>`)).join("")}</span></span>`;

/* Puts an open tooltip under its avatar, else above it, else beside it, always whole inside the viewport. */
function place(a) {
  const t = a.querySelector(".tip"), r = a.querySelector(".avb").getBoundingClientRect(), W = document.documentElement.clientWidth, H = innerHeight;
  const w = t.offsetWidth, h = t.offsetHeight, m = 8, g = 4;
  let top = r.bottom + g, left = r.left + r.width / 2 - w / 2;
  if (top + h > H - m) top = r.top - g - h;
  if (top < m) { top = Math.min(r.top, H - m - h); left = W - r.right >= r.left ? r.right + g : r.left - g - w; }
  t.style.left = Math.round(Math.max(m, Math.min(W - m - w, left))) + "px";
  t.style.top = Math.round(Math.max(m, top)) + "px";
}

const why = new WeakMap();
/* Adds or drops one reason (hover, focus, tap) an avatar's tooltip is open; open while any is left. */
function tip(a, reason, on) {
  const s = why.get(a) || new Set(), t = a.querySelector(".tip");
  on ? s.add(reason) : s.delete(reason);
  why.set(a, s);
  if (s.size && !t.matches(":popover-open")) { t.showPopover(); place(a); } else if (!s.size && t.matches(":popover-open")) t.hidePopover();
}

const avOf = (e) => e.target.closest && e.target.closest(".org .av");
/* A tap on an avatar toggles its tooltip; a tap anywhere else closes any tapped-open one. */
document.addEventListener("click", (e) => {
  const a = avOf(e);
  document.querySelectorAll(".org .av").forEach((x) => x !== a && why.get(x)?.has("tap") && tip(x, "tap", false));
  if (a) tip(a, "tap", !why.get(a)?.has("tap"));
});
document.addEventListener("pointerover", (e) => { const a = avOf(e); if (e.pointerType === "mouse" && a && !a.contains(e.relatedTarget)) tip(a, "hover", true); });
document.addEventListener("pointerout", (e) => { const a = avOf(e); if (e.pointerType === "mouse" && a && !a.contains(e.relatedTarget)) tip(a, "hover", false); });
document.addEventListener("focusin", (e) => { const a = avOf(e); if (a && e.target.matches(":focus-visible")) tip(a, "focus", true); });
document.addEventListener("focusout", (e) => { const a = avOf(e); if (a) tip(a, "focus", false); });
/* An open tooltip follows its avatar through a scroll or a resize. */
const follow = () => document.querySelectorAll(".org .tip:popover-open").forEach((t) => place(t.parentElement));
addEventListener("scroll", follow, { capture: true, passive: true });
addEventListener("resize", follow);

const worker = (p) => `<li title="${esc(titled(p))}">${who(p.id, `<span class="mini" aria-hidden="true">${familiar(p.id, p.pose === "working" ? "working" : "idle", "worker")}</span><b>${esc(p.name)}</b>${dot(p.state)}`)}</li>`;

/* The people at a seat's desks, working first: SHOWN of them, the rest folded behind a "hidden N" line. */
function crew(H) {
  if (!H.length) return "";
  const rest = H.slice(SHOWN);
  return `<div class="hang"><p class="hn">${plural(H.length, "worker")}, ${H.filter((p) => p.pose === "working").length} working</p><ul class="crew">${H.slice(0, SHOWN).map(worker).join("")}</ul>` +
    (rest.length ? `<details class="fold"><summary>hidden ${rest.length}</summary><ul class="folded">${rest.map(worker).join("")}</ul></details>` : "") + `</div>`;
}

/* A seat's card: avatar with its tooltip, name button, rank, state dot, its workers, the message link. */
function seatCard(p, H) {
  const s = p.raw, msg = "Message " + p.name;
  return `<div class="seat" data-seat="${esc(p.id)}">${av(p.id, p.name, familiar(p.id, p.state, p.role), [titled(p), s.area, s.about, ROLE[p.role], WAKE[s.wake], "Now " + p.state + "."])}` +
    `<h3>${who(p.id, esc(p.name))} ${p.rank ? `<span class="rk">${esc(p.rank)}</span>` : ""}${dot(p.state)}</h3>` +
    `${crew(H)}<a class="btn msg" href="#chat?ch=${esc(dmOf(p.id))}" aria-label="${esc(msg)}" title="${esc(msg)}">${BUBBLE}</a></div>`;
}

/* The seat tree: the CEO on top (the desk pool under it), every deeper level as a grid under its parent. */
function tree(M) {
  const rooms = M.rooms.filter((r) => r.kind === "seat"), pool = M.rooms.find((r) => r.kind === "pool");
  const sub = (id) => { const kids = rooms.filter((r) => r.people[0].raw.parent === id); return kids.length ? `<ol class="pos">` + kids.map((r) => `<li class="${esc(r.people[0].role)}">${seatCard(r.people[0], r.people.slice(1))}${sub(r.id)}</li>`).join("") + `</ol>` : ""; };
  return `<ol class="otree">` + (M.ceo ? `<li class="ceo">${seatCard(M.ceo.people[0], pool ? pool.people : [])}${sub(M.ceo.id)}</li>` : "") + `</ol>`;
}

const staffState = (p) => (p.pose === "working" ? "running" : p.pose === "error" ? "error" : p.raw.on ? "asleep" : "off");
const member = (p) => `<li>${who(p.id, `<span class="mini" aria-hidden="true">${familiar(p.id, p.pose === "working" ? "working" : "asleep", p.role)}</span><b>${esc(p.name)}</b><span class="rk">${esc(p.rank)}</span>${dot(staffState(p))}`)}</li>`;
const team = (r) => `<li class="team"><h3>${who(r.id, esc(r.name))}<span class="rk">${r.people.length} staff, ${r.busy} running</span></h3><ul class="mem">${r.people.map(member).join("")}</ul></li>`;

/* list(M) → HTML of the two list panes: who reports to whom, and the staff teams. */
export function list(M) {
  const seats = M.rooms.filter((r) => r.kind === "seat").length + (M.ceo ? 1 : 0), staff = M.staff.reduce((n, r) => n + r.people.length, 0);
  return `<section class="pane"><h2><span data-dec>who reports to whom</span><s>${plural(seats, "seat")}</s></h2>${tree(M)}</section>` +
    `<section class="pane"><h2><span data-dec>staff teams</span><s>${staff} staff</s></h2><ul class="teams">${M.staff.map(team).join("")}</ul></section>`;
}

/* Staff list: the office as plain text. The seat tree (a card per seat, its workers under it) and the staff teams; every name and avatar is a button that opens its card. */
import { esc } from "/static/js/core/fmt.js";
import { familiar } from "../../familiars/alive.js";
import { titled, dmOf } from "../../seats.js";
import { plural } from "../../summary.js";

const PILL = { working: "running", running: "running", idle: "idle", asleep: "off", off: "off", yours: "his", error: "failed" };
const SHOWN = 3;
const BUBBLE = '<svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v11H10l-5 4v-4H4z"/></svg>';

const dot = (st) => `<span class="pill dot ${PILL[st] || "idle"}" title="${esc(st)}"><span class="sr-only">${esc(st)}</span></span>`;
/* A section's status tag ("Paused"), its since date and note in its title; nothing while active. */
const tag = (s) => (s ? `<span class="ost" title="${esc([s.label + (s.since ? " since " + s.since : ""), s.note].filter(Boolean).join(" · "))}">${esc(s.label)}</span>` : "");
const who = (id, html) => `<button type="button" class="who" data-who="${esc(id)}">${html}</button>`;

/* An avatar button that opens the card of `id`; out of the tab order, the name button next to it is the one stop. */
const av = (id, name, art) => `<span class="av"><button type="button" class="avb" data-who="${esc(id)}" aria-label="About ${esc(name)}" tabindex="-1">${art}</button></span>`;

const worker = (p) => `<li title="${esc(titled(p))}">${who(p.id, `<span class="mini" aria-hidden="true">${familiar(p.id, p.pose === "working" ? "working" : "idle", "worker")}</span><b>${esc(p.name)}</b>${dot(p.state)}`)}</li>`;

/* The people at a seat's desks, working first: SHOWN of them, the rest folded behind a "hidden N" line. */
function crew(H) {
  if (!H.length) return "";
  const rest = H.slice(SHOWN);
  return `<div class="hang"><p class="hn">${plural(H.length, "worker")}, ${H.filter((p) => p.pose === "working").length} working</p><ul class="crew">${H.slice(0, SHOWN).map(worker).join("")}</ul>` +
    (rest.length ? `<details class="fold"><summary>hidden ${rest.length}</summary><ul class="folded">${rest.map(worker).join("")}</ul></details>` : "") + `</div>`;
}

/* A seat's card: avatar and name buttons that open its office card, rank, state dot, its workers, the message link. */
function seatCard(p, H) {
  const msg = "Message " + p.name;
  return `<div class="seat${p.raw.status ? " rest" : ""}" data-seat="${esc(p.id)}">${av(p.id, p.name, familiar(p.id, p.state, p.role))}` +
    `<h3>${who(p.id, esc(p.name))} ${p.rank ? `<span class="rk">${esc(p.rank)}</span>` : ""}${dot(p.state)}${tag(p.raw.status)}</h3>` +
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
const team = (r) => `<li class="team${r.status ? " rest" : ""}"><h3>${who(r.id, esc(r.name))}${tag(r.status)}<span class="rk">${r.people.length} staff, ${r.busy} running</span></h3><ul class="mem">${r.people.map(member).join("")}</ul></li>`;

/* list(M) → HTML of the two list panes: who reports to whom, and the staff teams. */
export function list(M) {
  const seats = M.rooms.filter((r) => r.kind === "seat").length + (M.ceo ? 1 : 0), staff = M.staff.reduce((n, r) => n + r.people.length, 0);
  return `<section class="pane"><h2><span data-dec>who reports to whom</span><s>${plural(seats, "seat")}</s></h2>${tree(M)}</section>` +
    `<section class="pane"><h2><span data-dec>staff teams</span><s>${staff} staff</s></h2><ul class="teams">${M.staff.map(team).join("")}</ul></section>`;
}

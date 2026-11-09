/* Org: who reports to whom (the seats of org.json) and every live Claude session on this laptop, from GET /api/org. */
import { esc } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import { creature } from "../avatar.js";
import { dust } from "../shapes.js";
import { fitEye } from "../gl/cam.js";
import { ago } from "./court.js";
import { plural } from "../summary.js";

export const own = true;
const STALE_MS = 20000;
const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const PILL = { working: "running", idle: "idle", asleep: "off", off: "off", yours: "his" };
const SHOWN = 3;
let O = null, at = 0, busy = false, err = "";

if (!document.querySelector('link[href="/static/css/org.css"]')) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = "/static/css/org.css";
  document.head.appendChild(l);
}

/* Reads /api/org when it is missing or older than STALE_MS, then repaints the screen if it is still on. */
function pull() {
  if (busy || (O && Date.now() - at < STALE_MS)) return;
  busy = true;
  getJSON("/api/org").then((j) => { O = j; err = ""; }, (e) => { err = e.message || "unreadable"; })
    .finally(() => { busy = false; at = Date.now(); if (cur === "org") go("org", true); });
}

const prot = (s) => !("pid" in s);
const pill = (st) => `<span class="pill ${PILL[st] || "idle"}">${esc(st)}</span>`;

/* A seat's state from its own sessions: working, idle, yours (a protected session), else asleep (or off for the always-on seat). */
export function seatState(seat, S) {
  const mine = S.filter((s) => s.seat === seat.id);
  if (mine.some(prot)) return "yours";
  if (mine.some((s) => s.state === "working")) return "working";
  if (mine.length) return "idle";
  return seat.wake === "channel" ? "off" : "asleep";
}

/* The owner's direct message with seat `id`, as Chat names it. */
export const dmOf = (id) => "dm-" + ["owner", id].sort().join("--");

const worker = (s) => `<li><span class="mini" aria-hidden="true">${creature("pid" + s.pid, s.state === "working" ? "working" : "idle", "worker")}</span><b>${esc(s.name || "pid " + s.pid)}</b>${pill(s.state)}</li>`;

/* The sessions a seat started, working first: SHOWN of them, the rest folded behind a "hidden N" line. */
function crew(H) {
  if (!H.length) return "";
  const all = [...H.filter((s) => s.state === "working"), ...H.filter((s) => s.state !== "working")], rest = all.slice(SHOWN);
  return `<div class="hang"><p class="hn">${plural(H.length, "worker")}, ${H.filter((s) => s.state === "working").length} working</p><ul class="crew">${all.slice(0, SHOWN).map(worker).join("")}</ul>` +
    (rest.length ? `<details class="fold"><summary>hidden ${rest.length}</summary><ul class="folded">${rest.map(worker).join("")}</ul></details>` : "") + `</div>`;
}

function seatCard(seat, S) {
  if (seat.role === "owner") return `<div class="seat him"><span class="av dia" aria-hidden="true"><i></i></span><h3>${esc(seat.name)}</h3><p><b>Read every channel, write anywhere, message anyone.</b></p><p>Only your words change what an agent may do.</p></div>`;
  const st = seatState(seat, S), helpers = S.filter((s) => !s.seat && s.parent === seat.id);
  return `<div class="seat" data-seat="${esc(seat.id)}"><span class="av" aria-hidden="true">${creature(seat.id, st === "working" || st === "idle" ? st : "sleep", seat.role)}</span><h3>${esc(seat.name)} ${pill(st)}</h3>` +
    `<p><b>${esc(ROLE[seat.role] || "")}</b></p><p>${esc(WAKE[seat.wake] || "")}</p>${crew(helpers)}<a class="btn msg" href="#chat?ch=${esc(dmOf(seat.id))}">Message</a></div>`;
}

/* The seat tree: the owner and the seats reporting to the owner one above the other, every deeper level as a grid under its parent. */
function sub(seats, S, id) {
  const kids = seats.filter((s) => s.parent === id);
  return kids.length ? `<ol class="pos">` + kids.map((s) => `<li class="${s.role}">${seatCard(s, S)}${sub(seats, S, s.id)}</li>`).join("") + `</ol>` : "";
}
function tree(seats, S) {
  const owner = seats.find((s) => s.role === "owner"), top = owner ? [owner, ...seats.filter((s) => s.parent === owner.id)] : [];
  return `<ol class="otree">` + top.map((s) => `<li class="${s.role}">${seatCard(s, S)}${s === owner ? "" : sub(seats, S, s.id)}</li>`).join("") + `</ol>`;
}

function row(s, names) {
  if (prot(s)) return `<tr class="dim"><td>protected project</td><td>${esc(names[s.seat] || "—")}</td><td>hidden</td><td>${pill(s.state === "working" ? "working" : "idle")}</td><td>—</td><td>${ago(s.since)} ago</td></tr>`;
  const seat = s.seat ? names[s.seat] || s.seat : s.parent ? "under " + (names[s.parent] || s.parent) : "—";
  return `<tr><td>${esc(s.name || "pid " + s.pid)}</td><td>${esc(seat)}</td><td class="dir">${esc(s.cwd)}</td><td>${pill(s.state)}</td><td>${esc(s.started_by || "—")}</td><td>${ago(s.since)} ago</td></tr>`;
}

export function render() {
  pull();
  if (!O) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">${err ? "org unreadable · " + esc(err) : "reading the org…"}</p></div>`;
  const S = O.sessions || [], seats = O.seats || [], names = Object.fromEntries(seats.map((s) => [s.id, s.name]));
  const work = S.filter((s) => s.state === "working").length;
  return `<div class="nxs org"><section class="band" aria-label="Org summary"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt"><p class="kin" data-dec>Org</p>` +
    `<p class="bsum"><b>${plural(S.length, "Claude session")} on this laptop</b>, ${work} working${err ? ` · stale: ${esc(err)}` : ""}</p></div></section><div class="ocols">` +
    `<section class="pane"><h2><span data-dec>who reports to whom</span><s>${plural(seats.length, "seat")}</s></h2>${tree(seats, S)}</section>` +
    `<section class="pane"><h2><span data-dec>every claude session</span><s>live session list</s></h2><table class="ses"><thead><tr><th>Session</th><th>Seat</th><th>Folder</th><th>State</th><th>Started by</th><th>Last active</th></tr></thead>` +
    `<tbody>${S.map((s) => row(s, names)).join("") || `<tr><td colspan="6">no live session</td></tr>`}</tbody></table></section></div></div>`;
}

/* The eye on the band's perch over a field of dust, as on the shared screens. */
export function scene() {
  const narrow = innerWidth < 820;
  return { key: "org", pts: dust(narrow ? 600 : 1500), box: document.getElementById("gl"), span: narrow ? 12 : 24, tilt: 0.25,
    eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

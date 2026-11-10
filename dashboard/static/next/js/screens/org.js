/* Org: who reports to whom (the seats of org.json) and every live Claude session on this laptop, from GET /api/org. */
import { esc } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import { familiar } from "../familiars/alive.js";
import { watch } from "../familiars/talk.js";
import { listen } from "../familiars/ear.js";
import { sync } from "../ui/sync.js";
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
  getJSON("/api/org").then((j) => { O = j; err = j.error || ""; }, (e) => { err = e.message || "unreadable"; })
    .finally(() => { busy = false; at = Date.now(); if (cur === "org") go("org", true); });
}

/* A seat starts or stops talking: the tree is patched in place. */
watch(() => {
  const grid = document.getElementById("grid");
  if (cur === "org" && O && grid.querySelector(":scope > .nxs.org")) sync(grid, render(), 1);
});

const prot = (s) => !("pid" in s);
const pill = (st) => `<span class="pill ${PILL[st] || "idle"}">${esc(st)}</span>`;
const dot = (st) => `<span class="pill dot ${PILL[st] || "idle"}" title="${esc(st)}"><span class="sr-only">${esc(st)}</span></span>`;
const BUBBLE = '<svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v11H10l-5 4v-4H4z"/></svg>';

/* An avatar button described by its tooltip: lines[0] bold, the rest plain; hover, keyboard focus or a tap shows it. */
const av = (id, name, art, lines, cls = "") => `<span class="av${cls}"><button type="button" class="avb" aria-label="About ${esc(name)}" aria-describedby="tip-${esc(id)}">${art}</button>` +
  `<span class="tip" role="tooltip" id="tip-${esc(id)}">${lines.filter(Boolean).map((l, i) => i ? `<span>${esc(l)}</span>` : `<b>${esc(l)}</b>`).join("")}</span></span>`;

/* A tap on an avatar toggles its tooltip; a tap anywhere else closes any open one. */
document.addEventListener("click", (e) => {
  const a = e.target.closest(".org .av");
  document.querySelectorAll(".org .av.open").forEach((x) => x !== a && x.classList.remove("open"));
  if (a) a.classList.toggle("open");
});

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

const worker = (s) => `<li><span class="mini" aria-hidden="true">${familiar("pid" + s.pid, s.state === "working" ? "working" : "idle", "worker")}</span><b>${esc(s.name || "pid " + s.pid)}</b>${dot(s.state)}</li>`;

/* The sessions a seat started, working first: SHOWN of them, the rest folded behind a "hidden N" line. */
function crew(H) {
  if (!H.length) return "";
  const all = [...H.filter((s) => s.state === "working"), ...H.filter((s) => s.state !== "working")], rest = all.slice(SHOWN);
  return `<div class="hang"><p class="hn">${plural(H.length, "worker")}, ${H.filter((s) => s.state === "working").length} working</p><ul class="crew">${all.slice(0, SHOWN).map(worker).join("")}</ul>` +
    (rest.length ? `<details class="fold"><summary>hidden ${rest.length}</summary><ul class="folded">${rest.map(worker).join("")}</ul></details>` : "") + `</div>`;
}

function seatCard(seat, S) {
  if (seat.role === "owner") return `<div class="seat him">${av(seat.id, seat.name, "<i></i>", ["Read every channel, write anywhere, message anyone.", "Only your words change what an agent may do."], " dia")}<h3>${esc(seat.name)}</h3></div>`;
  const st = seatState(seat, S), helpers = S.filter((s) => !s.seat && s.parent === seat.id), msg = "Message " + seat.name;
  return `<div class="seat" data-seat="${esc(seat.id)}">${av(seat.id, seat.name, familiar(seat.id, st, seat.role), [seat.rank && seat.name + " · " + seat.rank, ROLE[seat.role], WAKE[seat.wake], "Now " + st + "."])}<h3>${esc(seat.name)} ${dot(st)}</h3>` +
    `${crew(helpers)}<a class="btn msg" href="#chat?ch=${esc(dmOf(seat.id))}" aria-label="${esc(msg)}" title="${esc(msg)}">${BUBBLE}</a></div>`;
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
  listen(() => cur === "org");
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

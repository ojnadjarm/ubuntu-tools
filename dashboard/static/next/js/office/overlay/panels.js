/* The boards under the office: Next runs, Running now, Recent 24 h, Sessions and Claims, each a fold; Recent starts shut, on the phone all but Running now and Sessions too. */
import { esc } from "/static/js/core/fmt.js";
import { ago, until, progress } from "../time.js";

const CSS = "/static/css/office-panels.css", PHONE = "(max-width: 700px)", OPEN = new Set(["running", "sessions"]), SHUT = new Set(["recent"]);
const PILL = { working: "running", idle: "idle", done: "idle", error: "warn", stale: "stray" }, SAY = { stale: "stopped" };
const shut = {};
if (typeof document !== "undefined") {
  if (!document.querySelector(`link[href="${CSS}"]`)) document.head.appendChild(Object.assign(document.createElement("link"), { rel: "stylesheet", href: CSS }));
  /* A tap on a fold's summary is remembered, so the next repaint keeps it open or shut. */
  document.addEventListener("click", (e) => { const s = e.target.closest && e.target.closest(".opanels [data-panel] > summary"); if (s) shut[s.parentNode.dataset.panel] = s.parentNode.open; }, true);
}
const isOpen = (id) => !(id in shut ? shut[id] : SHUT.has(id) || (!OPEN.has(id) && typeof matchMedia === "function" && matchMedia(PHONE).matches));

/* One board: a fold with its title and count. */
const board = (id, title, n, body) => `<details class="pane ob" data-panel="${id}"${isOpen(id) ? " open" : ""}><summary><h2><span data-dec>${title}</span><s>${n}</s></h2></summary>${body}</details>`;

const pill = (st) => `<span class="pill ${PILL[st] || "idle"}">${esc(SAY[st] || st)}</span>`;
const session = (s) => `<tr${s.protected ? ' class="dim"' : ""}><td>${esc(s.session)}</td><td>${esc(s.seat)}</td><td class="dir">${esc(s.folder)}</td><td>${pill(s.state)}</td><td>${esc(s.by)}</td><td>${esc(ago(s.since))} ago</td></tr>`;
const next = (r) => { const p = Math.round(progress(r.last, r.next)); return `<li${r.bad ? ' class="bad"' : ""}><button type="button" class="who" data-who="${esc(r.id)}"><b>${esc(r.name)}</b></button>` +
  `${r.bad ? '<em class="bm">last run failed</em>' : ""}<span class="in">in ${esc(until(r.next))}</span><progress max="100" value="${p}" aria-label="${esc(r.name)}: ${p} % of the wait to the next run"></progress></li>`; };
/* An agent row in the Claims board's row shape: ticket, its pill and how long, then its label and what it does now or how it ended. */
const agent = (who, r, line, when) => `<li>${who}<em>${pill(r.state || "working")} ${esc(when)}</em>${[r.label, line].filter(Boolean).map((t) => `<span title="${esc(t)}">${esc(t)}</span>`).join("")}</li>`;
const running = (r) => agent(`<button type="button" class="who" data-who="${esc(r.id)}"><b>${esc(r.ticket)}</b></button>`, r, "now · " + (r.doing || "starting"), "running " + ago(r.started));
const recent = (r) => agent(`<b>${esc(r.ticket)}</b>`, r, r.report, ago(r.last) + " ago");
const claim = (c) => `<li><b>${esc(c.who)}</b><em>${esc(c.note)}</em>${c.paths.map((p) => `<span title="${esc(p.full)}">${esc(p.short)}</span>`).join("")}</li>`;

/* panels(M) → HTML of the boards. */
export function panels(M) {
  const { next: N, running: G, recent: E, sessions: S, claims: C } = M.panels;
  return board("next", "next runs, soonest first", N.length, `<ol class="onext">${N.map(next).join("") || "<li>no run scheduled</li>"}</ol>`) +
    board("running", "running now", G.length, `<ul class="claims">${G.map(running).join("") || "<li><span>nobody is working</span></li>"}</ul>`) +
    board("recent", "recent · 24 h", E.length + " ended", `<ul class="claims">${E.map(recent).join("") || "<li><span>nothing ended in the last 24 h</span></li>"}</ul>`) +
    board("sessions", "every claude session", S.length, `<table class="ses"><thead><tr><th>Session</th><th>Seat</th><th>Folder</th><th>State</th><th>Started by</th><th>Last active</th></tr></thead>` +
      `<tbody>${S.map(session).join("") || `<tr><td colspan="6">no live session</td></tr>`}</tbody></table>`) +
    board("claims", "claims board", C.length, `<ul class="claims">${C.map(claim).join("") || "<li><span>empty · nobody holds a file</span></li>"}</ul>`);
}

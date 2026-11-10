/* The boards under the office: the Sessions table, one row per live Claude session. */
import { esc } from "/static/js/core/fmt.js";
import { ago } from "../time.js";

const PILL = { working: "running", idle: "idle" };
const pill = (st) => `<span class="pill ${PILL[st] || "idle"}">${esc(st)}</span>`;
const row = (s) => `<tr${s.protected ? ' class="dim"' : ""}><td>${esc(s.session)}</td><td>${esc(s.seat)}</td><td class="dir">${esc(s.folder)}</td><td>${pill(s.state)}</td><td>${esc(s.by)}</td><td>${esc(ago(s.since))} ago</td></tr>`;

/* panels(M) → HTML of the boards. */
export function panels(M) {
  const S = M.panels.sessions;
  return `<section class="pane"><h2><span data-dec>every claude session</span><s>live session list</s></h2><table class="ses"><thead><tr><th>Session</th><th>Seat</th><th>Folder</th><th>State</th><th>Started by</th><th>Last active</th></tr></thead>` +
    `<tbody>${S.map(row).join("") || `<tr><td colspan="6">no live session</td></tr>`}</tbody></table></section>`;
}

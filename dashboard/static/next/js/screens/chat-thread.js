/* Chat thread markup shared by Agents › Chat and the office's talk panel: day lines, one sender's run grouped, quotes, attachments, actions and who is thinking.
   v = { ch, q, name(id), stateOf(id), roleOf(id), label(ch) }: the view the rows are drawn for. */
import { esc, p2 } from "/static/js/core/fmt.js";
import { familiar } from "../familiars/alive.js";
import { talking } from "../familiars/talk.js";
import { attachments } from "./chat-files.js";
import { actions, grouped, opened } from "./chat-actions.js";

const QUOTE = 44;
const TAG = { ask: `<span class="ctag">question</span>`, answer: `<span class="ctag ans">answer</span>` };

const time = (m) => { const d = new Date(m.ts); return p2(d.getHours()) + ":" + p2(d.getMinutes()); };
/* The <time> of m: its hours and minutes, the full local date and time as its title. */
const stamp = (m, cls = "") => `<time${cls ? ` class="${cls}"` : ""} datetime="${esc(m.ts)}" title="${esc(new Date(m.ts).toLocaleString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" }))}">${time(m)}</time>`;
function day(m) {
  const d = new Date(m.ts), now = new Date(), y = new Date(now - 864e5);
  if (d.toDateString() === now.toDateString()) return "Today";
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
}
const clip = (t) => (t.length > QUOTE ? t.slice(0, QUOTE).trimEnd() + "…" : t);

/* One row: a group's first row carries the Familiar and header (talking when mid is being said), a grouped row a gutter time; both the actions. */
function msg(m, byId, v, fmt, grp, mid) {
  if (m.kind === "system") return `<li class="csys">${fmt(m.text)}</li>`;
  const him = m.from === "owner", r = m.re != null ? byId[m.re] : null;
  const li = `<li class="msg${him ? " him" : ""}${grp ? " grp" : ""}${opened(m) ? " open" : ""}" data-mch="${esc(m.ch)}" data-mid="${esc(String(m.id))}">`;
  const body = `${m.text ? `<div class="tx">${fmt(m.text)}</div>` : ""}${attachments(m.files)}`, acts = actions(m, !!v.ch && !v.q);
  if (grp) return `${li}${stamp(m, "gt")}<div>${body}</div>${acts}</li>`;
  const av = him ? `<i class="dia"></i>` : familiar(m.from, v.stateOf(m.from), v.roleOf(m.from), mid);
  const re = m.re == null ? "" : `<p class="re">${r ? esc(v.name(r.from) + " " + time(r) + ": " + clip(r.text)) : "a reply to an earlier message"}</p>`;
  const where = v.ch ? "" : `<a class="chtag" href="#chat?ch=${esc(m.ch)}" data-ch="${esc(m.ch)}">${esc(v.label(m.ch))}</a>`;
  return `${li}<span class="av" aria-hidden="true">${av}</span><div><p class="who"><b>${esc(v.name(m.from))}</b>${where}${TAG[m.kind] || ""}${stamp(m)}</p>${re}${body}</div>${acts}</li>`;
}

/* "<seat> is thinking" (or "woken, starting") for an agent woken from channel t.ch and still running. */
export const busyLine = (t, v) => esc(v.name(t.seat)) + (t.state === "thinking" ? " is thinking" : " woken, starting");

/* The thinking rows of T for the view (every channel's when v.ch is empty). */
export function thinking(T, v) {
  return T.filter((t) => !v.ch || t.ch === v.ch).map((t) => {
    const where = v.ch ? "" : `<a class="chtag" href="#chat?ch=${esc(t.ch)}" data-ch="${esc(t.ch)}">${esc(v.label(t.ch))}</a>`;
    return `<li class="thinking"><span class="av" aria-hidden="true">${familiar(t.seat, "working", v.roleOf(t.seat))}</span><p><b>${busyLine(t, v)}</b><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>${where}</p></li>`;
  }).join("");
}

/* Rows of list with a day line before each new day, one sender's run grouped under its first row; fmt turns text to HTML. */
export function rows(list, v, fmt) {
  const byId = Object.fromEntries(list.map((m) => [m.id, m])), g = list.map((m, i) => grouped(list[i - 1], m));
  let last = "", out = "";
  list.forEach((m, i) => {
    const d = day(m);
    if (d !== last) { out += `<li class="cday">${esc(d)}</li>`; last = d; }
    let mid = m.id;
    for (let j = i + 1; !g[i] && j < list.length && g[j]; j++) if (talking(m.from, list[j].id)) mid = list[j].id;
    out += msg(m, byId, v, fmt, g[i], mid);
  });
  return out;
}

/* Chat: Recent (every channel, newest last) or a channel's stream (newest 50, older on scroll-up), the channels and direct messages, a composer with attachments, who is in it, who is thinking and today's wakes, from GET /api/chat. */
import { esc, p2 } from "/static/js/core/fmt.js";
import { getJSON, postJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import { familiar } from "../familiars/alive.js";
import { heard, watch as onTalk } from "../familiars/talk.js";
import { dust } from "../shapes.js";
import { fitEye } from "../gl/cam.js";
import { sync } from "../ui/sync.js";
import { plural } from "../summary.js";
import { seatState, dmOf } from "./org.js";
import { composer, bind, forget } from "./chat-compose.js";
import { attachments } from "./chat-files.js";
import { store } from "../store.js";

export const own = true;
const POLL_MS = 3000, ORG_MS = 20000, QUOTE = 44;
const DESC = { harness: "Product owners ask how the machine works. The orchestrator answers.", org: "The whole org: the orchestrator and every product owner." };
const PILL = { working: "running", idle: "idle", asleep: "off", off: "off", yours: "his" };
const LINE = { working: "working now", idle: "idle", asleep: "asleep, wakes on its name", off: "off", yours: "your session" };
const TAG = { ask: `<span class="ctag">question</span>`, answer: `<span class="ctag ans">answer</span>` };
const ROOMS = ["harness", "org"];
let C = null, msgs = [], ch = "", err = "", busy = false, timer = 0, O = null, oat = 0, stick = true, W = null;
let more = false, jump = true, early = false, io = null, watched = null, T = [];
const seen = {};

if (!document.querySelector('link[href="/static/css/chat.css"]')) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = "/static/css/chat.css";
  document.head.appendChild(l);
}

/* The hash carries the open channel: #chat?ch=<id>. */
export function read(q) {
  const want = new URLSearchParams(q).get("ch") || "";
  if (want !== ch) { ch = want; msgs = []; stick = true; jump = true; more = false; forget(); }
}
export const hash = () => "#chat" + (ch ? "?ch=" + encodeURIComponent(ch) : "");
if (location.hash.startsWith("#chat?")) read(location.hash.slice(6));

/* The query of the open view: a channel, or Recent (no channel). */
const src = (c) => "/api/chat?" + (c ? "ch=" + encodeURIComponent(c) : "recent=1");

/* One read of the open view (only what is newer than the last message), then the next one in POLL_MS while Chat is on screen. */
function pull() {
  if (busy) return;
  clearTimeout(timer); timer = 0; busy = true;
  const want = ch, after = msgs.length ? msgs[msgs.length - 1].id : null;
  if (!O || Date.now() - oat > ORG_MS) { oat = Date.now(); getJSON("/api/org").then((j) => { O = j; paint(); }, () => {}); }
  getJSON(src(want) + (after ? "&after=" + after : ""))
    .then((j) => {
      err = "";
      if (want !== ch) return;
      C = j.channels || []; W = j.wakes || null; T = j.thinking || [];
      msgs = after ? msgs.concat(j.messages || []) : j.messages || [];
      if (after) heard(j.messages || []);
      if (!after) more = !!j.more;
      markRead();
    }, (e) => { err = e.message || "unreadable"; })
    .finally(() => {
      busy = false;
      if (cur !== "chat" || document.hidden) return;
      timer = setTimeout(() => { timer = 0; if (cur === "chat" && !document.hidden) pull(); }, want === ch ? POLL_MS : 0);
      paint();
    });
}

/* The element that scrolls the stream: the stream box from 900 px, else the page. */
const scroller = (box) => (getComputedStyle(box).overflowY === "auto" ? box : document.scrollingElement);

/* The page before the oldest message shown, prepended without moving what he is reading. */
function older() {
  if (!more || early || !msgs.length) return;
  early = true;
  const want = ch;
  getJSON(src(want) + "&before=" + msgs[0].id)
    .then((j) => {
      if (want !== ch) return;
      const box = document.querySelector("#grid .chat .msgs"), s = box && scroller(box), h0 = s ? s.scrollHeight : 0;
      msgs = (j.messages || []).concat(msgs); more = !!j.more;
      paint();
      if (s) s.scrollTop += s.scrollHeight - h0;
    }, (e) => { err = e.message || "unreadable"; })
    .finally(() => { early = false; });
}

/* Loads older messages when the top of the stream comes into view. */
function watch(grid) {
  const top = grid.querySelector(".chat .older");
  if (top === watched) return;
  if (!io) io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) older(); }, { rootMargin: "200px 0px 0px 0px" });
  io.disconnect(); watched = top;
  if (top) io.observe(top);
}

/* After a send: repaint now, then read what is new at once. */
function paintNow() { clearTimeout(timer); timer = 0; paint(); pull(); }

/* Moves his read cursor to the newest message of the open channel once per new message; the badges follow. */
function markRead() {
  const c = C.find((x) => x.ch === ch), last = msgs.length ? msgs[msgs.length - 1].id : 0;
  store.chatUnread = C.reduce((t, x) => t + (x.ch === ch ? 0 : x.unread), 0);
  store.chrome();
  if (!c || !c.unread || !last || seen[ch] >= last || document.hidden) return;
  seen[ch] = last; c.unread = 0;
  postJSON("/api/chat/seen", { ch, id: last }).catch(() => {});
}

/* Repaints in place (the stream keeps its scroll) and keeps the newest message in view while he is at the bottom. */
function paint() {
  if (cur !== "chat") return;
  const grid = document.getElementById("grid"), box0 = grid.querySelector(".chat .msgs");
  if (box0) stick = box0.scrollHeight - box0.scrollTop - box0.clientHeight < 40;
  if (grid.querySelector(":scope > .nxs.chat")) sync(grid, render(), 1); else go("chat", true);
  const box = grid.querySelector(".chat .msgs");
  if (box && stick) box.scrollTop = box.scrollHeight;
  if (box && jump && msgs.length) { jump = false; const s = scroller(box); if (s !== box) s.scrollTop = s.scrollHeight; }
  watch(grid);
}

onTalk(() => paint());

const names = () => Object.fromEntries(((O && O.seats) || []).map((s) => [s.id, s.name]));
const nameOf = (id, N) => (id === "owner" ? "You" : N[id] || id);
const pair = (c) => c.slice(3).split("--");
/* Every channel he can open: the rooms and a direct message per seat even before a first message, then the agents' own direct messages. */
function listed() {
  const seats = ((O && O.seats) || []).filter((s) => s.role !== "owner"), have = (id) => C.find((c) => c.ch === id) || { ch: id, unread: 0 };
  const rooms = [...new Set([...ROOMS, ...seats.filter((s) => s.role === "po" && s.wake !== "pull").map((s) => s.id), ...C.filter((c) => !c.ch.startsWith("dm-")).map((c) => c.ch)])].map(have);
  const mine = seats.map((s) => have(dmOf(s.id)));
  return { rooms, dms: [...mine, ...C.filter((c) => c.ch.startsWith("dm-") && !mine.some((m) => m.ch === c.ch))] };
}
function label(c, N) {
  if (!c) return "Recent";
  if (!c.startsWith("dm-")) return "# " + c;
  const [a, b] = pair(c);
  return a === "owner" ? nameOf(b, N) : b === "owner" ? nameOf(a, N) : nameOf(a, N) + " · " + nameOf(b, N);
}
const roleOf = (id) => (((O && O.seats) || []).find((s) => s.id === id) || {}).role || "worker";
function stateOf(id) {
  const seat = ((O && O.seats) || []).find((s) => s.id === id);
  return seat ? seatState(seat, O.sessions || []) : "";
}

const time = (m) => { const d = new Date(m.ts); return p2(d.getHours()) + ":" + p2(d.getMinutes()); };
function day(m) {
  const d = new Date(m.ts), now = new Date(), y = new Date(now - 864e5);
  if (d.toDateString() === now.toDateString()) return "Today";
  if (d.toDateString() === y.toDateString()) return "Yesterday";
  return d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
}
/* Message text is data: escaped, only `code` spans become markup. */
const text = (t) => esc(t).replace(/`([^`\n]+)`/g, "<code>$1</code>");
const clip = (t) => (t.length > QUOTE ? t.slice(0, QUOTE).trimEnd() + "…" : t);

function msg(m, byId, N) {
  if (m.kind === "system") return `<li class="csys">${text(m.text)}</li>`;
  const him = m.from === "owner", r = m.re != null ? byId[m.re] : null;
  const av = him ? `<i class="dia"></i>` : familiar(m.from, stateOf(m.from), roleOf(m.from), m.id);
  const re = m.re == null ? "" : `<p class="re">${r ? esc(nameOf(r.from, N) + " " + time(r) + ": " + clip(r.text)) : "a reply to an earlier message"}</p>`;
  const where = ch ? "" : `<a class="chtag" href="#chat?ch=${esc(m.ch)}" data-ch="${esc(m.ch)}">${esc(label(m.ch, N))}</a>`;
  return `<li class="msg${him ? " him" : ""}"><span class="av" aria-hidden="true">${av}</span><div><p class="who"><b>${esc(nameOf(m.from, N))}</b>${where}${TAG[m.kind] || ""}<time datetime="${esc(m.ts)}">${time(m)}</time></p>${re}${m.text ? `<p class="tx">${text(m.text)}</p>` : ""}${attachments(m.files)}</div></li>`;
}
/* "<seat> is thinking" (or "woken, starting") for an agent woken from channel c and still running. */
const busyLine = (t, N) => esc(nameOf(t.seat, N)) + (t.state === "thinking" ? " is thinking" : " woken, starting");
function thinking(N) {
  return T.filter((t) => !ch || t.ch === ch).map((t) => {
    const where = ch ? "" : `<a class="chtag" href="#chat?ch=${esc(t.ch)}" data-ch="${esc(t.ch)}">${esc(label(t.ch, N))}</a>`;
    return `<li class="thinking"><span class="av" aria-hidden="true">${familiar(t.seat, "working", roleOf(t.seat))}</span><p><b>${busyLine(t, N)}</b><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>${where}</p></li>`;
  }).join("");
}
function stream(N) {
  const byId = Object.fromEntries(msgs.map((m) => [m.id, m]));
  let last = "", out = "";
  for (const m of msgs) {
    const d = day(m);
    if (d !== last) { out += `<li class="cday">${esc(d)}</li>`; last = d; }
    out += msg(m, byId, N);
  }
  return ((more ? `<li class="older"><button type="button" class="btn" data-older>Older messages</button></li>` : "") + out ||
    `<li class="csys">No messages ${ch ? "in this channel" : "anywhere"} yet.</li>`) + thinking(N);
}

function chanLink(c, N) {
  const who = c.ch.startsWith("dm-") ? pair(c.ch).find((s) => s !== "owner") || "" : "", st = who ? stateOf(who) : "";
  const think = T.filter((t) => t.ch === c.ch).map((t) => `<span class="think" title="${busyLine(t, N)}"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span></span>`).join("");
  const tail = c.unread ? `<span class="unread" title="${plural(c.unread, "unread message")}">${c.unread}</span>` : st && !think ? `<span class="pill ${PILL[st] || "idle"}">${esc(st)}</span>` : "";
  return `<a href="#chat${c.ch ? "?ch=" + esc(c.ch) : ""}" data-ch="${esc(c.ch)}"${c.ch === ch ? ` class="on" aria-current="page"` : ""}>${who ? familiar(who, st, roleOf(who)) : ""}<span class="cn">${esc(label(c.ch, N))}</span>${think}${tail}</a>`;
}
function members(N) {
  const ids = ch.startsWith("dm-") ? pair(ch) : [...new Set(msgs.filter((m) => m.kind !== "system").map((m) => m.from))];
  const rows = ids.filter((id) => id !== "owner").map((id) => {
    const st = stateOf(id);
    return `<div class="mem"><span class="av" aria-hidden="true">${familiar(id, st, roleOf(id))}</span><div><b>${esc(nameOf(id, N))}</b><span>${esc(LINE[st] || "not a seat of the org")}</span></div></div>`;
  });
  return rows.join("") || `<p class="none">Nobody has written here yet.</p>`;
}
/* Agent-caused wakes per seat today, a plain count (no limit); his own messages never count. */
function wakes(N) {
  if (!W) return "";
  const rows = ((O && O.seats) || []).filter((s) => s.role !== "owner" && s.wake !== "pull").map((s) => {
    const n = W.today[s.id] || 0;
    return `<div class="wk"><span>${esc(nameOf(s.id, N))}</span><b>${n}</b></div>`;
  });
  return `<section class="wakes" aria-label="Wakes today"><h2><span data-dec>wakes today</span></h2>${rows.join("") || `<p class="none">no seats</p>`}<p class="none">Agents only: your messages never count.</p></section>`;
}
function head(N) {
  if (!ch) return `<header><h2>Recent</h2><p>The newest messages of every channel, newest at the bottom. Open a channel to write.</p></header>`;
  const desc = ch.startsWith("dm-") ? "Direct messages between " + pair(ch).map((s) => nameOf(s, N)).join(" and ") + "." : DESC[ch] || (N[ch] ? N[ch] + "'s channel." : "");
  return `<header><h2>${esc(label(ch, N))}</h2>${desc ? `<p>${esc(desc)}</p>` : ""}</header>`;
}

export function render() {
  if (!timer && !busy) pull();
  if (!C) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">${err ? "chat unreadable · " + esc(err) : "reading the chat…"}</p></div>`;
  bind(paintNow, (id) => nameOf(id, names()), paint);
  const N = names(), { rooms, dms } = listed();
  const unread = C.filter((c) => c.unread && c.ch !== ch), n = msgs.filter((m) => m.kind !== "system").length;
  const sum = `<b>${esc(label(ch, N))}</b>, ${plural(n, "message")}` + (unread.length ? ` · <span class="gold">${unread.map((c) => `${c.unread} new in ${esc(label(c.ch, N))}`).join(", ")}</span>` : "");
  const nav = `<nav class="chans" aria-label="Channels">${chanLink({ ch: "", unread: 0 }, N)}<h3>Channels</h3>${rooms.map((c) => chanLink(c, N)).join("")}` +
    (dms.length ? `<h3>Direct</h3>${dms.map((c) => chanLink(c, N)).join("")}` : "") + `</nav>`;
  const body = `<section class="pane stream" aria-label="Messages">${head(N)}<ol class="msgs" aria-live="polite">${stream(N)}</ol>${ch ? composer(ch, label(ch, N)) : ""}</section>`;
  return `<div class="nxs chat"><section class="band" aria-label="Chat summary"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt"><p class="kin" data-dec>Chat</p>` +
    `<p class="bsum">${sum}${err ? ` · stale: ${esc(err)}` : ""}</p></div></section><div class="cgrid">${nav}${body}` +
    `<aside class="pane cside" aria-label="In this channel"><h2><span data-dec>in this channel</span></h2>${members(N)}${wakes(N)}</aside></div></div>`;
}

/* A tap on a channel opens it in place. */
export function click(e) {
  if (e.target.closest(".chat [data-older]")) { older(); return true; }
  const a = e.target.closest(".chat [data-ch]");
  if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return false;
  e.preventDefault();
  if (a.dataset.ch !== ch) { ch = a.dataset.ch; msgs = []; stick = true; jump = true; more = false; forget(); clearTimeout(timer); timer = 0; go("chat", true); pull(); }
  return true;
}

/* The eye on the band's perch over a field of dust, as on the Org screen. */
export function scene() {
  const narrow = innerWidth < 820;
  return { key: "chat", pts: dust(narrow ? 600 : 1500), box: document.getElementById("gl"), span: narrow ? 12 : 24, tilt: 0.25,
    eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

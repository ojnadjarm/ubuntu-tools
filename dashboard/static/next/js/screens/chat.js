/* Chat: Recent (every channel, newest last), a channel's stream or a search over every channel (newest 50, older on scroll-up), the channels and direct messages, a composer with attachments, who is in it, who is thinking and today's wakes, from GET /api/chat; below 900 px a messenger: the conversation list, then one conversation full screen. */
import { esc } from "/static/js/core/fmt.js";
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
import { store } from "../store.js";
import { note, seed, lastIn, byActivity, peek, when } from "./chat-list.js";
import { box, bindSearch, mark, words, fill, focusBox } from "./chat-search.js";
import { bindActions } from "./chat-actions.js";
import { rows, thinking, busyLine } from "./chat-thread.js";
import { keep, take } from "./chat-cache.js";

export const own = true;
const POLL_MS = 3000, ORG_MS = 20000;
const DESC = { harness: "Product owners ask how the machine works. The orchestrator answers.", org: "The whole org: the orchestrator and every product owner." };
const PILL = { working: "running", idle: "idle", asleep: "off", off: "off", yours: "his" };
const LINE = { working: "working now", idle: "idle", asleep: "asleep, wakes on its name", off: "off", yours: "your session" };
const ROOMS = ["harness", "org"];
let C = null, msgs = [], ch = "", err = "", busy = false, timer = 0, O = null, oat = 0, follow = false, W = null;
let more = false, jump = true, early = false, io = null, watched = null, T = [];
let listing = true, atList = false, listY = 0, fresh = 0, shown = "", ready = false;
let q = "", hits = null, asked = "", serr = "", from = ["", true], spushed = false, deg = "", paused = false;
const phone = matchMedia("(max-width: 899px)");
const seen = {};

if (!document.querySelector('link[href="/static/css/chat.css"]')) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = "/static/css/chat.css";
  document.head.appendChild(l);
}

/* Opens channel c ("" = Recent) with the rows kept from its last read, if any; the phone list shows when list is true. */
function open(c, list) {
  listing = list;
  if (c !== ch) { const k = take(c); ch = c; msgs = k ? k.msgs : []; more = k ? k.more : false; ready = !!k; jump = true; fresh = 0; forget(); }
}
/* The hash carries the open view: #chat?ch=<id>, #chat?recent=1 (Recent), #chat?q=<words> (search), #chat (the phone list; Recent from 900 px). */
export function read(s) {
  const u = new URLSearchParams(s), want = u.get("ch") || "", w = u.get("q") || "";
  if (w.trim().length >= 2) { if (!q) from = [ch, listing]; q = w; open("", false); return; }
  q = ""; hits = null; asked = ""; spushed = false;
  open(want, !want && u.get("recent") !== "1");
}
export const hash = () => "#chat" + (q ? "?q=" + encodeURIComponent(q) : ch ? "?ch=" + encodeURIComponent(ch) : listing ? "" : "?recent=1");
if (location.hash.startsWith("#chat?")) read(location.hash.slice(6));

/* The query of the open view: a search for words, a channel, or Recent (no channel). */
const src = (c, w) => (w ? "/api/chat/search?q=" + encodeURIComponent(w) : "/api/chat?" + (c ? "ch=" + encodeURIComponent(c) : "recent=1"));

/* The one read of a search: the newest 30 messages of every channel holding every word, oldest first. */
function look() {
  const w = q.trim();
  asked = w; hits = null; serr = "";
  getJSON(src("", w)).then((j) => { if (w === asked) { hits = j.messages || []; follow = true; } }, (e) => { if (w === asked) serr = e.message || "unreadable"; })
    .finally(() => { if (w === asked) paint(); });
}

/* Typing in the box: 2+ characters open or refine the search view (a history entry of its own), fewer return. */
function seek(v) {
  if (v.trim().length < 2) { if (q) leave(); return; }
  if (v === q) return;
  if (!q) { from = [ch, listing]; open("", false); q = v; history.pushState(over(from[1]), "", hash()); spushed = true; }
  else { q = v; history.replaceState(null, "", hash()); }
  paint();
}

/* Leaves the search view for the view he came from (history back when the search pushed an entry). */
function leave() {
  q = ""; hits = null; asked = ""; serr = ""; fill("");
  if (spushed) { spushed = false; history.back(); return; }
  open(from[0], from[1]); history.replaceState(null, "", hash()); show();
}

/* One read of the open view (only what is newer than the last message), kept for its next open, then the next one in POLL_MS while Chat is on screen. */
function pull() {
  if (busy) return;
  clearTimeout(timer); timer = 0; busy = true;
  const want = ch, after = msgs.length ? msgs[msgs.length - 1].id : null;
  if (!O || Date.now() - oat > ORG_MS) { oat = Date.now(); getJSON("/api/org").then((j) => { O = j; paint(); }, () => {}); }
  getJSON(src(want) + (after ? "&after=" + after : ""))
    .then((j) => {
      err = ""; deg = j.degraded || ""; paused = !!j.paused;
      if (want !== ch) return;
      C = j.channels || []; W = j.wakes || null; T = j.thinking || [];
      seed(C);
      const got = j.messages || [], box = document.querySelector("#grid .chat .msgs");
      if (after && got.length && box && !atEnd(box)) fresh += got.length;
      msgs = after ? msgs.concat(got) : got;
      note(got);
      if (after) heard(got);
      if (!after) more = !!j.more;
      ready = true; keep(want, { msgs, more });
      markRead();
    }, (e) => { err = e.message || "unreadable"; })
    .finally(() => {
      busy = false;
      if (cur !== "chat" || document.hidden) return;
      timer = setTimeout(() => { timer = 0; if (cur === "chat" && !document.hidden) pull(); }, want === ch ? POLL_MS : 0);
      paint();
    });
}

/* True while the stream box shows its newest line (or is not on screen). */
const atEnd = (box) => !box.clientHeight || box.scrollHeight - box.scrollTop - box.clientHeight < 40;

/* The page before the oldest message shown, prepended without moving what he is reading. */
function older() {
  if (!more || early || !msgs.length) return;
  early = true;
  const want = ch;
  getJSON(src(want) + "&before=" + msgs[0].id)
    .then((j) => {
      if (want !== ch) return;
      const s = document.querySelector("#grid .chat .msgs"), h0 = s ? s.scrollHeight : 0;
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

/* After a send: repaint now, then read what is new at once and show it. */
function paintNow() { clearTimeout(timer); timer = 0; follow = true; paint(); pull(); }

/* Moves his read cursor to the newest message of the open channel once per new message; the badges follow. */
function markRead() {
  const c = C.find((x) => x.ch === ch), last = msgs.length ? msgs[msgs.length - 1].id : 0;
  store.chatUnread = C.reduce((t, x) => t + (x.ch === ch ? 0 : x.unread), 0);
  store.chrome();
  if (!c || !c.unread || !last || seen[ch] >= last || document.hidden) return;
  seen[ch] = last; c.unread = 0;
  postJSON("/api/chat/seen", { ch, id: last }).catch(() => {});
}

/* Repaints in place: only the stream box scrolls, and only to the newest line when he was already there (or just sent);
   otherwise it keeps his place and the "new messages" pill counts what came. */
function paint() {
  if (cur !== "chat") return;
  const grid = document.getElementById("grid"), box0 = grid.querySelector(".chat .msgs"), top = box0 ? box0.scrollTop : 0;
  const end = !box0 || atEnd(box0);
  if (end) fresh = 0;
  if (grid.querySelector(":scope > .nxs.chat")) sync(grid, render(), 1); else go("chat", true);
  fill(q);
  fit();
  const box = grid.querySelector(".chat .msgs");
  if (box && ((jump && msgs.length) || follow || end)) { box.scrollTop = box.scrollHeight; follow = false; if (msgs.length && box.scrollHeight > box.clientHeight) jump = false; }
  else if (box) box.scrollTop = top;
  watch(grid);
}

/* From 900 px: --chat-out = the page's height above and below the chat, measured, so the chat fills the screen exactly. */
function fit() {
  const c = cur === "chat" && !phone.matches && document.querySelector("#grid > .nxs.chat"), board = document.getElementById("board");
  if (!c || !board) return;
  const r = c.getBoundingClientRect(), below = board.getBoundingClientRect().bottom - r.bottom + parseFloat(getComputedStyle(document.body).paddingBottom);
  c.parentElement.style.setProperty("--chat-out", Math.ceil(r.top + scrollY + below) + "px");
}

onTalk(() => paint());
phone.addEventListener("change", () => { stack(false); paint(); });
addEventListener("resize", fit);
/* Scrolled down to the newest line by hand: the pill goes. */
document.addEventListener("scroll", (e) => { if (fresh && e.target.matches && e.target.matches("#grid .chat .msgs") && atEnd(e.target)) { fresh = 0; paint(); } }, true);
/* Browser back and forward between the phone list and a conversation; a link into a conversation gets the list under it. */
addEventListener("hashchange", () => {
  if (cur !== "chat" || !location.hash.startsWith("#chat")) return;
  read(location.hash.slice(6));
  stack(atList);
  if (shown !== ch + "|" + listing + "|" + q) show();
});

/* The history state of a phone view with the conversation list one entry below it. */
const over = (list) => (list && phone.matches ? { overList: true } : null);
const isOver = () => !!(history.state && history.state.overList);
/* On the phone a conversation (or Recent) always sits one entry above the list, so Back shows the list and Back again leaves Chat:
   reached from the list the entry is only marked, from anywhere else the list is put under it. */
function stack(fromList) {
  if (cur !== "chat" || !phone.matches || listing || q || isOver()) return;
  const h = hash();
  if (!fromList) { history.replaceState(null, "", "#chat"); history.pushState(over(true), "", h); }
  else history.replaceState(over(true), "", h);
}
/* Entering Chat (a cold open, a reload, a link or the tab reopening the last conversation). */
export function enter() { stack(false); }

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
function label(c, N, bare) {
  if (!c) return "Recent";
  if (!c.startsWith("dm-")) return "# " + c;
  const [a, b] = pair(c);
  const one = bare ? nameOf : ranked;
  return a === "owner" ? one(b, N) : b === "owner" ? one(a, N) : nameOf(a, N) + " · " + nameOf(b, N);
}
/* A seat's name, then its rank when the API gives one ("DarkSaddler · CEO"). */
const ranked = (id, N) => { const r = (((O && O.seats) || []).find((s) => s.id === id) || {}).rank; return nameOf(id, N) + (r ? " · " + r : ""); };
const roleOf = (id) => (((O && O.seats) || []).find((s) => s.id === id) || {}).role || "worker";
function stateOf(id) {
  const seat = ((O && O.seats) || []).find((s) => s.id === id);
  return seat ? seatState(seat, O.sessions || []) : "";
}

/* Message text is data: escaped, only `code` spans become markup. */
const text = (t) => esc(t).replace(/`([^`\n]+)`/g, "<code>$1</code>");
/* Message text to HTML: text() until chat-text.js's rich loads (absent: text() stays). */
let rich = text;
import("./chat-text.js").then((m) => { rich = m.rich; paint(); }, () => {});
/* The open view as chat-thread.js draws it. */
const view = (N) => ({ ch, q, name: (id) => nameOf(id, N), stateOf, roleOf, label: (c) => label(c, N) });

/* The search view's rows: Recent's rows with each word marked, or why there are none. */
function found(N) {
  if (serr) return `<li class="csys">Search failed: ${esc(serr)}</li>`;
  if (!hits) return `<li class="csys">Searching…</li>`;
  if (!hits.length) return `<li class="csys">No message has ${esc(q.trim())}.</li>`;
  const ws = words(q);
  return rows(hits, view(N), (t) => mark(rich(t), ws));
}
function stream(N) {
  const out = rows(msgs, view(N), rich);
  return ((more ? `<li class="older"><button type="button" class="btn" data-older>Older messages</button></li>` : "") + out ||
    `<li class="csys">${ready ? `No messages ${ch ? "in this channel" : "anywhere"} yet.` : "reading…"}</li>`) + thinking(T, view(N));
}

function chanLink(c, N) {
  const who = c.ch.startsWith("dm-") ? pair(c.ch).find((s) => s !== "owner") || "" : "", st = who ? stateOf(who) : "";
  const think = T.filter((t) => t.ch === c.ch).map((t) => `<span class="think" title="${busyLine(t, view(N))}"><span class="dots" aria-hidden="true"><i></i><i></i><i></i></span></span>`).join("");
  const tail = c.unread ? `<span class="unread" title="${plural(c.unread, "unread message")}">${c.unread}</span>` : st && !think ? `<span class="pill ${PILL[st] || "idle"}">${esc(st)}</span>` : "";
  const m = lastIn(c.ch), dm = c.ch.startsWith("dm-"), glyph = who ? "" : `<span class="glyph" aria-hidden="true">${c.ch ? "#" : "◆"}</span>`;
  const pv = `<span class="pv">${m ? esc(peek(m, (id) => nameOf(id, N), dm)) : !c.ch ? "Every channel, newest first" : C.some((x) => x.ch === c.ch) ? "" : "No messages yet"}</span>${m ? `<time class="tm" datetime="${esc(m.ts)}">${esc(when(m))}</time>` : ""}`;
  return `<a href="#chat${c.ch ? "?ch=" + esc(c.ch) : "?recent=1"}" data-ch="${esc(c.ch)}"${c.ch === ch && !q ? ` class="on" aria-current="page"` : ""}>${who ? familiar(who, st, roleOf(who)) : glyph}<span class="cn">${esc(label(c.ch, N))}</span>${pv}${think}${tail}</a>`;
}
/* Who is in the open view: the direct message's pair, else the senders of its messages (of the results in a search). */
function members(N) {
  const ids = ch.startsWith("dm-") ? pair(ch) : [...new Set((q ? hits || [] : msgs).filter((m) => m.kind !== "system").map((m) => m.from))];
  const rows = ids.filter((id) => id !== "owner").map((id) => {
    const st = stateOf(id);
    return `<div class="mem"><span class="av" aria-hidden="true">${familiar(id, st, roleOf(id))}</span><div><b>${esc(ranked(id, N))}</b><span>${esc(LINE[st] || "not a seat of the org")}</span></div></div>`;
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
/* The open view's title and description; below 900 px also a back arrow, the seat's Familiar and its state or who is thinking. */
function head(N) {
  const back = `<a class="back" href="#chat" data-back aria-label="Back to the conversations"><span aria-hidden="true">←</span></a>`;
  if (q) return `<header class="find">${back}${box(q, "cq2")}<h2>${esc(serr ? "Search failed" : hits ? plural(hits.length, "result") + " for " + q.trim() : "Searching for " + q.trim() + "…")}</h2></header>`;
  if (!ch) return `<header>${back}<span class="hav"><span class="glyph" aria-hidden="true">◆</span></span><h2>Recent</h2><p class="desc">The newest messages of every channel, newest at the bottom. Open a channel to write.</p><p class="st">Every channel, read only</p></header>`;
  const dm = ch.startsWith("dm-"), who = dm ? pair(ch).find((s) => s !== "owner") || "" : "", st = who ? stateOf(who) : "";
  const area = who && (((O && O.seats) || []).find((s) => s.id === who) || {}).area;
  const desc = dm ? "Direct messages between " + pair(ch).map((s) => nameOf(s, N)).join(" and ") + "." + (area ? " " + nameOf(who, N) + " works on " + area + "." : "") : DESC[ch] || (N[ch] ? N[ch] + "'s channel." : "");
  const busyNow = T.filter((t) => t.ch === ch), av = who ? familiar(who, st, roleOf(who)) : `<span class="glyph" aria-hidden="true">#</span>`;
  const line = busyNow.length ? busyNow.map((t) => busyLine(t, view(N))).join(", ") + `<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>` : esc(who ? LINE[st] || "" : desc);
  return `<header>${back}<span class="hav" aria-hidden="true">${av}</span><h2>${esc(label(ch, N))}</h2>${desc ? `<p class="desc">${esc(desc)}</p>` : ""}<p class="st">${line}</p></header>`;
}

export function render() {
  if (!timer && !busy) pull();
  if (!C) return `<div class="nxs skel" aria-busy="true"><p class="sm pad">${err ? "chat unreadable · " + esc(err) : "reading the chat…"}</p></div>`;
  bind(paintNow, (id) => nameOf(id, names()), paint);
  bindSearch(seek, () => { if (q) leave(); });
  bindActions((c, id) => { const m = (q ? hits || [] : msgs).find((x) => x.id === id && x.ch === c); return m ? { ch: m.ch, id: m.id, name: nameOf(m.from, names()), text: m.text } : null; });
  if (q && q.trim() !== asked) look();
  shown = ch + "|" + listing + "|" + q; atList = listing && !q;
  const N = names(), L = listed(), rooms = byActivity(L.rooms), dms = byActivity(L.dms);
  const unread = C.filter((c) => c.unread && c.ch !== ch), n = msgs.filter((m) => m.kind !== "system").length;
  const sum = (q ? `<b>Search</b>${hits ? ", " + plural(hits.length, "result") : ""}` : `<b>${esc(label(ch, N))}</b>, ${plural(n, "message")}`) + (unread.length ? ` · <span class="gold">${unread.map((c) => `${c.unread} new in ${esc(label(c.ch, N))}`).join(", ")}</span>` : "");
  const nav = `<nav class="chans" aria-label="Channels">${box(q, "cq")}${chanLink({ ch: "", unread: 0 }, N)}<h3>Channels</h3>${rooms.map((c) => chanLink(c, N)).join("")}` +
    (dms.length ? `<h3>Direct</h3>${dms.map((c) => chanLink(c, N)).join("")}` : "") + `</nav>`;
  const body = `<section class="pane stream" aria-label="Messages">${head(N)}<ol class="msgs" aria-live="polite">${q ? found(N) : stream(N)}</ol><button type="button" class="btn newer" data-newer${fresh && !q ? "" : " hidden"}>${plural(fresh, "new message")} ↓</button>${ch ? composer(ch, label(ch, N, true)) : ""}</section>`;
  return `<div class="nxs chat ${listing && !ch ? "list" : "conv"}"><section class="band" aria-label="Chat summary"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt"><p class="kin" data-dec>Chat</p>` +
    `<p class="bsum">${sum}${err ? ` · stale: ${esc(err)}` : ""}${paused ? " · wakes paused" : ""}${deg ? ` · degraded: ${esc(deg)}` : ""}</p></div></section><div class="cgrid">${nav}${body}` +
    `<aside class="pane cside" aria-label="In ${q ? "these results" : "this channel"}"><h2><span data-dec>in ${q ? "these results" : "this channel"}</span></h2>${members(N)}${wakes(N)}</aside></div></div>`;
}

/* Paints the view the state names, in place when Chat is on screen (a newly opened one at its newest line), and reads it at once; back on the phone list, at the scroll he left it. */
function show() {
  clearTimeout(timer); timer = 0;
  if (cur === "chat" && document.querySelector("#grid > .nxs.chat")) { paint(); if (location.hash !== hash()) history.replaceState(history.state, "", hash()); stack(false); }
  else go("chat", true);
  fill(q);
  if (listing && phone.matches) scrollTo(0, listY);
  pull();
}

/* A tap on a channel opens it in place (on the phone list as a new history entry, so Back returns to the list);
   the back arrow returns to the list; the pill jumps to the newest line. */
export function click(e) {
  if (e.target.closest(".chat [data-older]")) { older(); return true; }
  if (e.target.closest(".chat [data-newer]")) { const box = document.querySelector("#grid .chat .msgs"); if (box) box.scrollTop = box.scrollHeight; fresh = 0; paint(); return true; }
  if (e.target.closest(".chat [data-back]")) {
    e.preventDefault();
    if (q) { leave(); return true; }
    if (isOver()) { history.back(); return true; }
    open("", true); history.replaceState(null, "", hash()); show();
    return true;
  }
  const a = e.target.closest(".chat [data-ch]");
  if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return false;
  e.preventDefault();
  const was = q;
  if (q) { q = ""; hits = null; asked = ""; spushed = false; }
  if (a.dataset.ch === ch && !listing && !was) return true;
  if (phone.matches && listing && a.closest(".chans")) { listY = scrollY; open(a.dataset.ch, false); history.pushState(over(true), "", hash()); }
  else open(a.dataset.ch, false);
  show();
  return true;
}

/* "/" puts him in the search box; Esc leaves the search view. */
export function key(e) {
  if (e.key === "/" && focusBox()) { e.preventDefault(); return true; }
  if (e.key === "Escape" && q) { leave(); return true; }
  return false;
}

/* The eye on the band's perch over a field of dust, as on the Org screen. */
export function scene() {
  const narrow = innerWidth < 820;
  return { key: "chat", pts: dust(narrow ? 600 : 1500), box: document.getElementById("gl"), span: narrow ? 12 : 24, tilt: 0.25,
    eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

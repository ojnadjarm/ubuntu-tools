/* The office's talk panel: one direct message in a modal dialog over the live office (history, who is thinking, attachments, the composer),
   read every 3 s while open; the rows and the composer are Agents › Chat's own (chat-thread.js, chat-compose.js). */
import { esc } from "/static/js/core/fmt.js";
import { getJSON, postJSON } from "/static/js/core/api.js";
import { familiar } from "../../familiars/alive.js";
import { sync } from "../../ui/sync.js";
import { store } from "../../store.js";
import { seatState } from "../../seats.js";
import { rows, thinking, busyLine } from "../../screens/chat-thread.js";
import { composer, bind, forget } from "../../screens/chat-compose.js";
import { bindActions } from "../../screens/chat-actions.js";
import { rich } from "../../screens/chat-text.js";
import { movable } from "../../ui/drag.js";

const POLL_MS = 3000, ORG_MS = 20000;
const LINE = { working: "working now", idle: "idle", asleep: "asleep, wakes on its name", off: "off", yours: "your session" };
const WIDE = matchMedia("(min-width: 900px)");
const DOTS = `<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>`;
const spot = {};
let el = null, mover = null, ch = "", msgs = [], T = [], more = false, ready = false, err = "", O = null, oat = 0, timer = 0, busy = false, early = false, seen = 0, follow = false;

for (const href of ["/static/css/chat.css", "/static/css/office-talk.css"]) if (!document.querySelector(`link[href="${href}"]`)) {
  const l = document.createElement("link");
  l.rel = "stylesheet"; l.href = href;
  document.head.appendChild(l);
}

const seat = (id) => ((O && O.seats) || []).find((s) => s.id === id);
const name = (id) => (id === "owner" ? "You" : (seat(id) || {}).name || id);
const stateOf = (id) => { const s = seat(id); return s ? seatState(s, O.sessions || []) : ""; };
const roleOf = (id) => (seat(id) || {}).role || "worker";
const view = () => ({ ch, q: "", name, stateOf, roleOf, label: (c) => "# " + c });
const other = () => ch.slice(3).split("--").find((s) => s !== "owner") || "";
const atEnd = (box) => !box.clientHeight || box.scrollHeight - box.scrollTop - box.clientHeight < 40;

/* The one dialog, made on first use: ×, a click outside it, Esc (the dialog's own cancel) and Open in Chat close it; from 900 px its header moves it, to the spot kept for the page's life. */
function host() {
  if (el) return el;
  el = document.createElement("dialog");
  el.className = "otalk";
  el.addEventListener("click", (e) => {
    if (e.target === el) { const r = el.getBoundingClientRect(); if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) close(); return; }
    if (e.target.closest("[data-shut], [data-full]")) close();
    else if (e.target.closest("[data-older]")) older();
  });
  el.addEventListener("close", stop);
  document.body.append(el);
  mover = movable(el, { handle: ".ohead", when: () => WIDE.matches, spot });
  return el;
}

/* The panel's markup: the seat's Familiar, name, state or who is thinking, Open in Chat, ×; the stream; the composer. */
function html() {
  const who = other(), st = stateOf(who), s = seat(who) || {}, v = view(), busyNow = T.filter((t) => t.ch === ch);
  const line = busyNow.length ? busyNow.map((t) => busyLine(t, v)).join(", ") + DOTS : esc(LINE[st] || "");
  const list = (more ? `<li class="older"><button type="button" class="btn" data-older>Older messages</button></li>` : "") + rows(msgs, v, rich) ||
    `<li class="csys">${ready ? "No messages yet." : "reading…"}</li>`;
  return `<div class="chat"><section class="stream" aria-label="Messages"><div class="ohead"><span class="ofig" aria-hidden="true">${familiar(who, st, roleOf(who))}</span>` +
    `<h2>${esc(name(who))}${s.rank ? `<span>${esc(s.rank)}</span>` : ""}</h2><p class="st">${line}${err ? ` · stale: ${esc(err)}` : ""}</p>` +
    `<a class="btn ofull" href="#chat?ch=${esc(ch)}" data-full>Open in Chat</a><button type="button" class="cx" data-shut aria-label="Close">×</button></div>` +
    `<ol class="msgs" aria-live="polite">${list}${thinking(T, v)}</ol>${composer(ch, name(who))}</section></div>`;
}

/* Repaints in place (the box keeps its text and focus); the stream follows the newest line only when it was there or he just sent. */
function paint() {
  if (!isOpen()) return;
  const b0 = el.querySelector(".msgs"), end = !b0 || atEnd(b0), top = b0 ? b0.scrollTop : 0;
  sync(el, html());
  el.setAttribute("aria-label", "Talk to " + name(other()));
  const box = el.querySelector(".msgs");
  if (follow || end) { box.scrollTop = box.scrollHeight; follow = false; } else box.scrollTop = top;
}

/* Moves his read cursor to the newest message of the open channel; the Chat badge follows. */
function markRead(C) {
  const c = C.find((x) => x.ch === ch), last = msgs.length ? msgs[msgs.length - 1].id : 0;
  store.chatUnread = C.reduce((t, x) => t + (x.ch === ch ? 0 : x.unread), 0);
  store.chrome();
  if (!c || !c.unread || !last || seen >= last || document.hidden) return;
  seen = last;
  postJSON("/api/chat/seen", { ch, id: last }).catch(() => {});
}

/* One read of what is newer than the last row (and /api/org every 20 s), then the next in POLL_MS while open and visible. */
function pull() {
  if (busy || !isOpen()) return;
  clearTimeout(timer); timer = 0; busy = true;
  const want = ch, after = msgs.length ? msgs[msgs.length - 1].id : null;
  if (!O || Date.now() - oat > ORG_MS) { oat = Date.now(); getJSON("/api/org").then((j) => { O = j; paint(); }, () => {}); }
  getJSON("/api/chat?ch=" + encodeURIComponent(want) + (after ? "&after=" + after : "")).then((j) => {
    if (want !== ch) return;
    err = ""; T = j.thinking || [];
    const got = j.messages || [];
    msgs = after ? msgs.concat(got) : got;
    if (!after) more = !!j.more;
    ready = true;
    markRead(j.channels || []);
  }, (e) => { err = e.message || "unreadable"; }).finally(() => {
    busy = false;
    if (isOpen() && !document.hidden) timer = setTimeout(pull, POLL_MS);
    paint();
  });
}

/* The page before the oldest row, prepended without moving what he reads. */
function older() {
  if (!more || early || !msgs.length) return;
  early = true;
  const want = ch;
  getJSON("/api/chat?ch=" + encodeURIComponent(want) + "&before=" + msgs[0].id).then((j) => {
    if (want !== ch || !isOpen()) return;
    const box = el.querySelector(".msgs"), h0 = box.scrollHeight, top = box.scrollTop;
    msgs = (j.messages || []).concat(msgs); more = !!j.more;
    paint();
    box.scrollTop = top + box.scrollHeight - h0;
  }, () => {}).finally(() => { early = false; });
}

/* The phone keyboard: the sheet keeps to the visual viewport, so the composer stays above the keyboard. */
function fitKeys() {
  const v = window.visualViewport;
  if (!v || !isOpen()) return;
  el.style.setProperty("--vvh", v.height + "px");
  el.style.setProperty("--vvt", v.offsetTop + "px");
}

function stop() {
  clearTimeout(timer); timer = 0;
  forget();
  if (window.visualViewport) { visualViewport.removeEventListener("resize", fitKeys); visualViewport.removeEventListener("scroll", fitKeys); }
}

export const isOpen = () => !!el && el.open;

/* Opens channel c (a direct message "dm-a--b") over the office and reads it at once; the box takes focus where there is a keyboard. */
export function open(c) {
  const d = host();
  if (c !== ch) { ch = c; msgs = []; T = []; more = false; ready = false; seen = 0; }
  err = ""; follow = true;
  forget();
  bind(() => { follow = true; paint(); pull(); }, name, paint);
  bindActions((c2, id) => { const m = msgs.find((x) => x.id === id && x.ch === c2); return m ? { ch: m.ch, id: m.id, name: name(m.from), text: m.text } : null; });
  d.innerHTML = "";
  if (!d.open) d.showModal();
  if (window.visualViewport) { visualViewport.addEventListener("resize", fitKeys); visualViewport.addEventListener("scroll", fitKeys); fitKeys(); }
  paint();
  mover.place();
  if (!matchMedia("(pointer: coarse)").matches) { const box = d.querySelector("#say"); if (box) box.focus(); }
  pull();
}

export function close() { if (isOpen()) el.close(); }

/* Closes the panel and removes its node: the Office screen left the page. */
export function drop() {
  if (!el) return;
  close(); el.remove(); el = mover = null;
}

document.addEventListener("visibilitychange", () => { if (!document.hidden && isOpen() && !timer && !busy) pull(); });

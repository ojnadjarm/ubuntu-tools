/* Chat @ list (T1545-E): `@` at a word start in the composer lists the seats he can wake (name, id, state); typing filters,
   Up/Down move, Enter, Tab or a tap insert `@<id> `, Esc closes. Pure helpers, the list's state and markup, one binder. */
import { esc } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { seatState } from "./org.js";

const MENTION = /(?<![\w@.-])@([a-z0-9][a-z0-9-]*)/g;
const LIST = "mention-list", ORG_MS = 20000;
const PILL = { working: "running", idle: "idle", asleep: "off", off: "off", yours: "his" };
let O = null, oat = 0;
const S = { open: false, start: 0, shut: -1, at: 0, items: [] };

/* Seats a mention can wake: every seat but the owner and pull seats. */
export const wakeable = (org) => ((org && org.seats) || []).filter((s) => s.role !== "owner" && s.wake !== "pull");

/* The @ token the caret is in ({start, q}), or null; an @ after a word, @, . or - (a@b) is no mention. */
export function token(text, caret) {
  const m = /(?:^|[^\w@.-])@([a-z0-9-]*)$/i.exec(text.slice(0, caret));
  return m ? { start: caret - m[1].length - 1, q: m[1].toLowerCase() } : null;
}

/* Seats whose id or name holds q. */
export const filter = (seats, q) => seats.filter((s) => s.id.includes(q) || (s.name || "").toLowerCase().includes(q));

/* text with the token from start to the caret (and its tail) replaced by `@id `; the caret after it. */
export function insert(text, start, caret, id) {
  const head = text.slice(0, start) + "@" + id + " ";
  return { text: head + text.slice(caret).replace(/^[\w-]*\s?/, ""), caret: head.length };
}

/* Wakeable seats the text mentions, first mention first (the server's rule in lib/chat_route.py). */
export function mentioned(text, seats) {
  const ids = [...new Set([...text.toLowerCase().matchAll(MENTION)].map((m) => m[1]))];
  return ids.map((id) => seats.find((s) => s.id === id)).filter(Boolean);
}

/* Seats a send of text would wake by mention, from the last /api/org read. */
export const wakesIn = (text) => mentioned(text || "", wakeable(O));

const optId = (id) => "mention-" + id;
function row(s, i) {
  const st = seatState(s, (O && O.sessions) || []);
  return `<li role="option" id="${esc(optId(s.id))}" data-id="${esc(s.id)}" aria-selected="${i === S.at}"><span class="nm">${esc(s.name || s.id)}</span><span class="id">@${esc(s.id)}</span><span class="pill ${PILL[st] || "idle"}">${esc(st)}</span></li>`;
}
/* The listbox as the state has it (hidden while closed). */
export const listbox = () => `<ul class="mention" id="${LIST}" role="listbox" aria-label="Agents to wake"${S.open ? "" : " hidden"}>${S.open ? S.items.map(row).join("") : ""}</ul>`;
const active = () => (S.open ? optId(S.items[S.at].id) : "");
/* The textarea's combobox attributes as the state has them. */
export const boxAttrs = () => ` role="combobox" aria-autocomplete="list" aria-controls="${LIST}" aria-expanded="${S.open}"${S.open ? ` aria-activedescendant="${esc(active())}"` : ""}`;

/* Writes the state into the live box and list, the same as a repaint would. */
function show(box) {
  box.setAttribute("aria-expanded", String(S.open));
  if (S.open) box.setAttribute("aria-activedescendant", active()); else box.removeAttribute("aria-activedescendant");
  const ul = box.form && box.form.querySelector("#" + LIST);
  if (!ul) return;
  ul.outerHTML = listbox();
  const on = S.open && document.getElementById(active());
  if (on) on.scrollIntoView({ block: "nearest" });
}
/* Opens, filters or closes the list for the caret's token. */
export function update(box) {
  const t = token(box.value, box.selectionStart);
  if (!t) S.shut = -1;
  const items = t && t.start !== S.shut ? filter(wakeable(O), t.q) : [];
  if (S.open && t && t.start === S.start && items.length === S.items.length && items.every((s, i) => s.id === S.items[i].id)) return;
  S.items = items; S.open = items.length > 0; S.at = 0; S.start = t ? t.start : 0;
  show(box);
}
/* Closes the list and forgets an Esc. */
export function reset() { S.open = false; S.items = []; S.shut = -1; }

/* Puts `@id ` at the token and tells the composer the text changed. */
function pick(box, id) {
  const r = insert(box.value, S.start, box.selectionStart, id);
  box.value = r.text; box.setSelectionRange(r.caret, r.caret);
  S.open = false; S.items = [];
  show(box);
  box.dispatchEvent(new Event("input", { bubbles: true }));
}

/* A key in the box while the list is open: true when the list took it (Enter then does not send). */
export function key(e) {
  if (!S.open || e.isComposing || e.altKey || e.ctrlKey || e.metaKey) return false;
  const box = e.target, n = S.items.length;
  if (e.key === "ArrowDown" || e.key === "ArrowUp") S.at = (S.at + (e.key === "ArrowDown" ? 1 : n - 1)) % n, show(box);
  else if ((e.key === "Enter" && !e.shiftKey) || (e.key === "Tab" && !e.shiftKey)) pick(box, S.items[S.at].id);
  else if (e.key === "Escape") { S.shut = S.start; S.open = false; S.items = []; show(box); }
  else return false;
  e.preventDefault();
  return true;
}

/* Reads /api/org when older than ORG_MS; then() runs once seats are fresh. */
export function load(then) {
  if (O && Date.now() - oat < ORG_MS) return;
  oat = Date.now();
  getJSON("/api/org").then((j) => { O = j; then(); }, () => { oat = 0; });
}

let bound = false;
/* Once: a tap on a row inserts it (focus stays in the box); leaving the box or a caret move by tap re-reads the token. */
export function bindMention() {
  if (bound) return;
  bound = true;
  document.addEventListener("mousedown", (e) => { if (e.target.closest(".chat .compose .mention")) e.preventDefault(); });
  document.addEventListener("click", (e) => {
    const o = e.target.closest(".chat .compose .mention [role=option]"), box = o && o.closest("form").querySelector("textarea");
    if (box) { box.focus(); pick(box, o.dataset.id); }
  });
  document.addEventListener("focusout", (e) => { if (S.open && e.target.matches(".chat .compose textarea")) { S.open = false; S.items = []; show(e.target); } });
  document.addEventListener("pointerup", (e) => { if (e.target.matches(".chat .compose textarea")) update(e.target); });
}

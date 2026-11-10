/* The office pop-up: the card of the person or room that was tapped, a top-layer popover placed by its anchor; a seat that posts talks on it for 2 s. */
import { esc } from "/static/js/core/fmt.js";
import { creature } from "../../avatar.js";
import { talking, watch } from "../../familiars/talk.js";
import { sync } from "../../ui/sync.js";
import { card } from "../fields.js";

let M = null, el = null;

/* The one card element, made on first use. */
function host() {
  if (el) return el;
  el = document.createElement("div");
  el.id = "office-card"; el.className = "ocard"; el.popover = "auto"; el.tabIndex = -1;
  el.setAttribute("role", "dialog"); el.setAttribute("aria-label", "About");
  document.body.append(el);
  return el;
}

const safe = (href) => (/^(#|https?:\/\/)/.test(href) ? href : "#");
const chip = (p) => `<li><button type="button" class="chip ${esc(p.pose)}" data-who="${esc(p.id)}"><i></i>${esc(p.name)}<span>${esc(p.note ?? p.rank)}</span></button></li>`;
const CLOSE = `<button type="button" class="cx" data-close aria-label="Close">×</button>`;
const dl = (rows) => `<dl>${rows.map(([k, v, tone]) => `<dt>${esc(k)}</dt><dd${tone ? ` class="${esc(tone)}"` : ""}>${esc(v)}</dd>`).join("")}</dl>`;
/* One titled part of a card: its rows, its chips, else its one quiet line. */
const part = (x) => `<section class="cpart"><h3>${esc(x.h)}</h3>` + (x.rows.length ? dl(x.rows) : "") + (x.chips.length ? `<ul class="roll">${x.chips.map(chip).join("")}</ul>` : "") +
  (x.rows.length || x.chips.length ? "" : `<p class="quiet">${esc(x.empty)}</p>`) + `</section>`;

/* Markup of the card of p (a person or a room). */
function html(p) {
  const c = card(p), pose = talking(p.id) ? "talking" : c.state.pose;
  return CLOSE + (p.people ? "" : `<div class="cfig${c.dim ? " dim" : ""}" aria-hidden="true">${creature(p.id, talking(p.id) ? "talking" : p.pose, p.role)}</div>`) +
    `<div class="cbody"><h2>${esc(c.title)}${c.rank ? `<span><b class="sr-only"> · </b>${esc(c.rank)}</span>` : ""}</h2>` + (c.sub ? `<p class="area">${esc(c.sub)}</p>` : "") +
    (c.lines || []).map((l) => `<p class="ln">${esc(l)}</p>`).join("") +
    `<p class="st ${esc(pose)}${c.dim ? " dim" : ""}"><i></i>${esc(c.state.text)}</p>` +
    (c.bar != null ? `<progress max="100" value="${Math.round(c.bar)}" aria-label="To the next run"></progress>` : "") +
    (c.rows.length ? dl(c.rows) : "") +
    (c.home ? `<p class="home"><button type="button" class="chip" data-who="${esc(c.home.id)}">${esc(c.home.text)}</button></p>` : "") +
    (c.roll ? (c.parts ? `<h3>Members</h3>` : "") + (c.roll.length ? `<ul class="roll">${c.roll.map((id) => M.who[id]).filter(Boolean).map(chip).join("")}</ul>` : `<p class="quiet">nobody here</p>`) : "") +
    (c.parts || []).map(part).join("") +
    (c.actions || []).map((a) => `<a class="btn" href="${esc(safe(a.href))}">${esc(a.label)}</a>`).join("") + `</div>`;
}

/* Opens the card of `id` under the viewport point `anchor` {x, y}, else above it, and moves focus into it (closing gives it back); without an anchor it stays where it is. */
export function open(id, anchor) {
  const p = M && M.who[id], c = host();
  if (!p) return;
  c.innerHTML = html(p); c.dataset.for = id; c.setAttribute("aria-label", "About " + p.name);
  const shown = c.matches(":popover-open");
  if (!shown) c.showPopover();
  if (!c.contains(document.activeElement)) c.focus({ preventScroll: true });
  if (innerWidth <= 600) { c.style.left = c.style.top = ""; return; }
  if (!anchor && shown) return;
  const a = anchor || { x: innerWidth / 2, y: innerHeight / 3 }, w = c.offsetWidth, h = c.offsetHeight, m = 8, g = 10;
  c.style.left = Math.round(Math.max(m, Math.min(document.documentElement.clientWidth - m - w, a.x - w / 2))) + "px";
  c.style.top = Math.round(Math.max(m, a.y + g + h > innerHeight - m ? Math.min(a.y - g - h, innerHeight - m - h) : a.y + g)) + "px";
}

/* Takes the new model; an open card redraws its rows, or closes when its subject is gone. */
export function refresh(next) {
  M = next;
  if (!isOpen()) return;
  const p = M.who[el.dataset.for];
  if (p) sync(el, html(p)); else close();
}

watch(() => { if (M) refresh(M); });

export const isOpen = () => !!el && el.matches(":popover-open");
export function close() { if (isOpen()) el.hidePopover(); }

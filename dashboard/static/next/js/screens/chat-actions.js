/* Per-message actions (Reply, Copy), the grouping rule for one sender's run of messages and the one click/tap binder (T1545-F). */
import { copyText } from "/static/js/ui/copy.js";

const GAP = 5 * 60000, FLASH_MS = 1500;
const tapUI = matchMedia("(max-width: 899px), (hover: none)");
let open = "", flash = "", label = "", get = null, bound = false;
const keyOf = (m) => m.ch + "|" + m.id;

/* True when m continues prev's run: same sender and channel, same day, within 5 min, plain messages, no quote. */
export function grouped(prev, m) {
  if (!prev || prev.from !== m.from || prev.ch !== m.ch || prev.kind !== "msg" || m.kind !== "msg" || m.re != null) return false;
  const a = new Date(prev.ts), b = new Date(m.ts);
  return a.toDateString() === b.toDateString() && b - a <= GAP;
}

/* Whether m's actions were opened by a tap. */
export const opened = (m) => open === keyOf(m);

/* The actions of m: Reply (only where a composer exists) and Copy; data-mch/data-mid sit on the row. */
export function actions(m, reply) {
  const copy = flash === keyOf(m) ? label : "Copy";
  return `<span class="act">${reply ? `<button type="button" class="btn" data-reply>Reply</button>` : ""}<button type="button" class="btn" data-mcopy>${copy}</button></span>`;
}

/* Binds the actions once; find(ch, id) gives {ch, id, name, text} of a shown message or null. */
export function bindActions(find) {
  get = find;
  if (bound) return;
  bound = true;
  document.addEventListener("click", onClick);
}

/* Shows "Copied" (or why not) on the button for FLASH_MS, kept through repaints. */
function say(b, k, ok) {
  flash = k; label = ok ? "Copied" : "Copy failed"; b.textContent = label;
  setTimeout(() => {
    if (flash !== k) return;
    flash = "";
    const li = [...document.querySelectorAll(".chat .msgs .msg[data-mid]")].find((x) => x.dataset.mch + "|" + x.dataset.mid === k);
    const c = li && li.querySelector("[data-mcopy]");
    if (c) c.textContent = "Copy";
  }, FLASH_MS);
}

/* Copy, Reply, and on touch or below 900 px a tap on a row toggles its actions (a tap elsewhere closes them). */
function onClick(e) {
  const li = e.target.closest && e.target.closest(".chat .msgs .msg[data-mid]");
  const k = li ? li.dataset.mch + "|" + li.dataset.mid : "", m = li && get ? get(li.dataset.mch, +li.dataset.mid) : null;
  const copy = e.target.closest && e.target.closest("[data-mcopy]"), reply = e.target.closest && e.target.closest("[data-reply]");
  if (m && copy) { copyText(m.text).then(() => say(copy, k, true), () => say(copy, k, false)); return; }
  if (m && reply) {
    document.dispatchEvent(new CustomEvent("chat:reply", { detail: m }));
    const box = document.getElementById("say");
    if (box) box.focus();
    return;
  }
  let next = open;
  if (!li) next = "";
  else if (tapUI.matches && !e.target.closest("a, button, input, textarea, summary, label, .cb") && !String(getSelection())) next = open === k ? "" : k;
  if (next === open) return;
  open = next;
  document.querySelectorAll(".chat .msgs .msg.open").forEach((x) => x.classList.remove("open"));
  if (open && li) li.classList.add("open");
}

/* Chat search: the "Search messages" box, its 250 ms debounce and keys, and the matched words marked in result HTML. */
import { esc } from "/static/js/core/fmt.js";

const DEBOUNCE_MS = 250, SEL = ".chat .csq input";
let wait = 0, bound = false;

/* The box with query q; id tells the channel list's box from the phone search header's. */
export const box = (q, id) =>
  `<div class="csq" role="search"><input id="${id}" type="search" aria-label="Search messages" placeholder="Search messages" title="Search messages (/)" autocomplete="off" spellcheck="false" enterkeyhint="search" value="${esc(q)}"></div>`;

/* The words of query q. */
export const words = (q) => q.trim().split(/\s+/).filter(Boolean);

/* html with every word wrapped in <mark>, in text nodes only (never in a tag, an attribute or a button label). */
export function mark(html, ws) {
  if (!ws.length) return html;
  const re = new RegExp(ws.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).sort((a, b) => b.length - a.length).join("|"), "gi");
  const t = document.createElement("template");
  t.innerHTML = html;
  const walk = document.createTreeWalker(t.content, NodeFilter.SHOW_TEXT), hit = [];
  for (let n = walk.nextNode(); n; n = walk.nextNode()) if (n.nodeValue.search(re) >= 0 && !(n.parentElement && n.parentElement.closest("button"))) hit.push(n);
  for (const n of hit) {
    const s = n.nodeValue, f = document.createDocumentFragment();
    let i = 0;
    for (const m of s.matchAll(re)) {
      const k = document.createElement("mark");
      k.textContent = m[0];
      f.append(s.slice(i, m.index), k);
      i = m.index + m[0].length;
    }
    f.append(s.slice(i));
    n.replaceWith(f);
  }
  return t.innerHTML;
}

const shown = (el) => el.checkVisibility({ visibilityProperty: true });

/* Focuses the box on screen and selects its text; false when none is shown. */
export function focusBox() {
  const b = [...document.querySelectorAll(SEL)].find(shown);
  if (b) { b.focus(); b.select(); }
  return !!b;
}

/* Puts q in every box he is not typing in. */
export function fill(q) {
  for (const b of document.querySelectorAll(SEL)) if (b !== document.activeElement && b.value !== q) b.value = q;
}

/* Runs find(value) and keeps him typing in the box on screen when the new view hid the one he typed in. */
function run(el, find) {
  const had = document.activeElement === el;
  find(el.value);
  if (!had || shown(el)) return;
  const b = [...document.querySelectorAll(SEL)].find(shown);
  if (b) { b.value = el.value; b.focus(); b.setSelectionRange(b.value.length, b.value.length); }
}

/* Wires the boxes once: typing calls find(value) after 250 ms of quiet (Enter at once), Esc clears them and calls quit(). */
export function bindSearch(find, quit) {
  if (bound) return;
  bound = true;
  document.addEventListener("input", (e) => {
    if (!e.target.matches(SEL)) return;
    clearTimeout(wait);
    const el = e.target;
    wait = setTimeout(() => { wait = 0; run(el, find); }, DEBOUNCE_MS);
  });
  document.addEventListener("keydown", (e) => {
    if (!e.target.matches(SEL)) return;
    if (e.key === "Enter") { e.preventDefault(); clearTimeout(wait); run(e.target, find); }
    else if (e.key === "Escape") { e.preventDefault(); clearTimeout(wait); e.target.value = ""; e.target.blur(); fill(""); quit(); }
  });
}

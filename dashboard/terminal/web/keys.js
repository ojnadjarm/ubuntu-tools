/* Key bar for the ttyd shell in the iframe: sends Esc, Tab, arrows and symbols; Ctrl arms for the next typed key. */
const SEQ = { esc: "\x1b", tab: "\t", "^c": "\x03", up: "\x1b[A", down: "\x1b[B", right: "\x1b[C", left: "\x1b[D" };
const frame = document.getElementById("tty"), ctrl = document.querySelector('[data-k="ctrl"]');
let armed = false, hooked = null;

const term = () => { try { return frame.contentWindow.term; } catch (e) { return null; } };
function send(s) { const t = term(); if (!t) return; t.input(s, true); t.focus(); }
function arm(on) { armed = on; ctrl.setAttribute("aria-pressed", String(on)); hook(); if (on) { const t = term(); if (t) t.focus(); } }
const ctrlOf = (c) => (/^[a-z@\[\\\]^_ ]$/i.test(c) ? String.fromCharCode(c.toUpperCase().charCodeAt(0) & 0x1f) : c);

/* Catches the next key typed into the shell (hardware keydown or soft-keyboard beforeinput) while Ctrl is armed. */
function hook() {
  const doc = frame.contentDocument;
  if (!doc || hooked === doc) return;
  hooked = doc;
  const take = (e, c) => { if (!armed || !c || c.length !== 1) return; e.preventDefault(); e.stopImmediatePropagation(); arm(false); send(ctrlOf(c)); };
  doc.addEventListener("keydown", (e) => { if (!e.ctrlKey && !e.altKey && !e.metaKey) take(e, e.key); }, true);
  doc.addEventListener("beforeinput", (e) => take(e, e.data), true);
}

document.getElementById("keys").addEventListener("pointerdown", (e) => {
  const b = e.target.closest("button");
  if (!b) return;
  e.preventDefault();
  const k = b.dataset.k;
  if (k === "ctrl") arm(!armed);
  else send(SEQ[k] || (armed ? (arm(false), ctrlOf(k)) : k));
});
frame.addEventListener("load", hook);

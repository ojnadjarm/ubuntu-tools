/* Full screen for the office: html.ofill lays the stage over the dashboard chrome, and where the browser has element fullscreen (desktop,
   Android, iPad) the page itself goes full screen too; iPhone Safari has none, so there it only fills the window. The page (not the stage)
   is the fullscreen element, so the card and the talk panel keep their place in the top layer above the stage. */
const doc = document.documentElement;
const fsEl = () => document.fullscreenElement || document.webkitFullscreenElement || null;
const native = () => !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);

export const isFull = () => doc.classList.contains("ofill");

/* The stage button, labelled for the current mode. */
export const button = () => `<button type="button" id="office-full" aria-pressed="${isFull()}">${isFull() ? "Exit full screen" : "Full screen"}</button>`;

function fill(on) {
  doc.classList.toggle("ofill", on);
  const b = document.getElementById("office-full");
  if (b) { b.setAttribute("aria-pressed", String(on)); b.textContent = on ? "Exit full screen" : "Full screen"; }
}

/* Enters full screen, or leaves it. */
export function toggle() {
  if (isFull()) { leave(); return; }
  fill(true);
  if (native()) Promise.resolve((doc.requestFullscreen || doc.webkitRequestFullscreen).call(doc)).catch(() => {});
}

/* Leaves full screen (the office left the page, Esc, or the button). */
export function leave() {
  if (fsEl()) (document.exitFullscreen || document.webkitExitFullscreen).call(document);
  if (isFull()) fill(false);
}

/* The browser left full screen by itself (Esc, F11): the stage goes back into the page. */
for (const ev of ["fullscreenchange", "webkitfullscreenchange"]) document.addEventListener(ev, () => { if (!fsEl() && isFull()) fill(false); });

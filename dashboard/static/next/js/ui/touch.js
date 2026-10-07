/* Haptic light without sound: a ring leaves every press, pressed cards dip and flash, a light follows the pointer over cards; the stage hears both. */
import { store } from "../store.js";

const fine = matchMedia("(hover: hover) and (pointer: fine)");
const LIT = ".pane, .nx .cell, .band";

export function bindTouch() {
  const rings = [0, 1].map(() => { const r = document.createElement("i"); r.className = "press"; r.setAttribute("aria-hidden", "true"); document.body.appendChild(r); return r; });
  let ri = 0;
  addEventListener("pointerdown", (e) => {
    if (store.stage) store.stage.press(e.clientX, e.clientY);
    if (!e.target.closest("a, button, .pane, .cell, [data-nav], summary, label")) return;
    const r = rings[ri++ % 2];
    r.style.transform = `translate3d(${e.clientX}px,${e.clientY}px,0)`;
    r.classList.remove("go"); void r.offsetWidth; r.classList.add("go");
  }, { passive: true });
  addEventListener("pointermove", (e) => {
    const mouse = e.pointerType === "mouse";
    if (store.stage) store.stage.pointer(e.clientX, e.clientY, mouse);
    if (!mouse || !fine.matches) return;
    const el = e.target.closest && e.target.closest(LIT);
    if (!el) return;
    const b = el.getBoundingClientRect();
    el.style.setProperty("--mx", (e.clientX - b.left).toFixed(0) + "px"); el.style.setProperty("--my", (e.clientY - b.top).toFixed(0) + "px");
  }, { passive: true });
  document.documentElement.addEventListener("pointerleave", () => { if (store.stage) store.stage.leave(); });
}

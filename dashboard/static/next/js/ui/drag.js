/* Moves a position: fixed box by a handle with pointer events (mouse, touch, pen), always inside the window; the spot lives in the caller's object. */
const SKIP = "a, button, input, textarea, select, label, [contenteditable]";
const SLOP_PX = 4;

/* box: the fixed element; handle: selector of the grab area inside it; when(): moving applies now (else the CSS place); spot: {x, y} kept by the caller. */
export function movable(box, { handle, when = () => true, spot = {} }) {
  let grab = null, moved = false;

  /* Puts the box at the spot, pulled back inside the window; with no spot, or when() is false, the stylesheet places it. */
  function place() {
    if (!box.isConnected) { removeEventListener("resize", place); return; }
    if (!when() || spot.x == null) { box.style.left = box.style.top = box.style.right = box.style.bottom = ""; return; }
    const r = box.getBoundingClientRect(), d = document.documentElement;
    spot.x = Math.round(Math.min(Math.max(0, spot.x), Math.max(0, d.clientWidth - r.width)));
    spot.y = Math.round(Math.min(Math.max(0, spot.y), Math.max(0, d.clientHeight - r.height)));
    Object.assign(box.style, { left: spot.x + "px", top: spot.y + "px", right: "auto", bottom: "auto" });
  }

  box.addEventListener("pointerdown", (e) => {
    moved = false;
    if (e.button !== 0 || !when() || !e.target.closest(handle) || e.target.closest(SKIP)) return;
    const r = box.getBoundingClientRect();
    grab = { id: e.pointerId, dx: e.clientX - r.left, dy: e.clientY - r.top, x0: e.clientX, y0: e.clientY };
    box.setPointerCapture(e.pointerId);
    e.preventDefault();
  });
  box.addEventListener("pointermove", (e) => {
    if (!grab || e.pointerId !== grab.id) return;
    if (!moved && Math.hypot(e.clientX - grab.x0, e.clientY - grab.y0) < SLOP_PX) return;
    moved = true;
    spot.x = e.clientX - grab.dx; spot.y = e.clientY - grab.dy;
    place();
  });
  for (const t of ["pointerup", "pointercancel", "lostpointercapture"]) box.addEventListener(t, (e) => { if (grab && e.pointerId === grab.id) grab = null; });
  /* The click that ends a move is not a click: nothing inside or outside the box hears it. */
  box.addEventListener("click", (e) => { if (moved) { moved = false; e.stopImmediatePropagation(); e.preventDefault(); } }, true);
  addEventListener("resize", place);
  return { place };
}

/** A shot: centre and size of the region to frame, in drawing units (y up). */
export interface Box { x: number; y: number; w: number; h: number }
/** Screen pixels at the top and bottom that page chrome covers; the shot is fitted between them. */
export interface Inset { top: number; bottom: number }
/** Axis-aligned rectangle [x0, y0, x1, y1] in drawing units. */
export type Rect = [number, number, number, number];

export const DEFAULT_INSET: Inset = { top: 28, bottom: 164 };

/** Title block size, the height of its optional signature strip and its inset from the sheet border, in drawing units. */
export const TITLE = { w: 560, h: 176, sign: 40, margin: 16 };

/** Where the title block of a sheet box sits (bottom-right corner); a signed block is taller by the signature strip. */
export function titleRect(sheet: Rect, signed = false): Rect {
  const x1 = sheet[2] - TITLE.margin, y0 = sheet[1] + TITLE.margin;
  return [x1 - TITLE.w, y0, x1, y0 + TITLE.h + (signed ? TITLE.sign : 0)];
}

/** Scale, camera centre and visible rectangle for shot b in a W × H viewport (the Stage uses exactly this). */
export function frameView(b: Box, W: number, H: number, inset: Inset = DEFAULT_INSET): { s: number; cx: number; cy: number; view: Rect } {
  const free = H - inset.top - inset.bottom;
  const s = Math.min(W / b.w, free / b.h);
  const uc = inset.top + free / 2;
  const cx = b.x, cy = b.y + (uc - H / 2) / s;
  const hw = W / (2 * s), hh = H / (2 * s);
  return { s, cx, cy, view: [cx - hw, cy - hh, cx + hw, cy + hh] };
}

/** True when r is partly on screen: an object the frame cuts through (a title block, a legend, a figure). */
export function cuts(view: Rect, r: Rect): boolean {
  const meets = r[0] < view[2] && r[2] > view[0] && r[1] < view[3] && r[3] > view[1];
  const inside = r[0] >= view[0] && r[2] <= view[2] && r[1] >= view[1] && r[3] <= view[3];
  return meets && !inside;
}

/** Every (shot, viewport, object) where the frame cuts an object that must be shown whole or not at all. */
export function framingFaults(shots: Record<string, Box>, whole: Record<string, Rect>, viewports: [number, number][], inset: Inset = DEFAULT_INSET): string[] {
  const out: string[] = [];
  for (const [name, b] of Object.entries(shots)) {
    for (const [W, H] of viewports) {
      const { view } = frameView(b, W, H, inset);
      for (const [id, r] of Object.entries(whole)) if (cuts(view, r)) out.push(`${name} @ ${W}x${H} cuts ${id}`);
    }
  }
  return out;
}

/**
 * The nearest shot to `b` that cuts nothing in `whole` and holds every `need` id fully inside, on every viewport (null if none in range).
 * Searches ±300 units of pan and 0.8–1.4× of size; nearness = |dx| + |dy| + 600·|zoom − 1|.
 */
export function fitShot(b: Box, whole: Record<string, Rect>, need: string[] = [], viewports: [number, number][] = DESKTOP, inset: Inset = DEFAULT_INSET): Box | null {
  const holds = (v: Rect, r: Rect): boolean => r[0] >= v[0] && r[2] <= v[2] && r[1] >= v[1] && r[3] <= v[3];
  const ok = (n: Box): boolean => !framingFaults({ n }, whole, viewports, inset).length
    && viewports.every(([W, H]) => need.every((id) => holds(frameView(n, W, H, inset).view, whole[id])));
  let best: Box | null = null, cost = Infinity;
  for (let dx = -300; dx <= 300; dx += 20) for (let dy = -300; dy <= 300; dy += 10) for (let k = 0.8; k <= 1.401; k += 0.05) {
    const c = Math.abs(dx) + Math.abs(dy) + 600 * Math.abs(k - 1);
    if (c >= cost) continue;
    const n = { x: b.x + dx, y: b.y + dy, w: Math.round(b.w * k), h: Math.round(b.h * k) };
    if (ok(n)) { best = n; cost = c; }
  }
  return best;
}

/** One moment of a plate's script: where the camera is and how far each state key is shown (0 = hidden). */
export interface Sample { t: number; cam: Box; show: Record<string, number> }

/**
 * Cuts the viewer can actually see: at every sample where the camera is held (same box as the sample before) and the plate is exposed,
 * each object in `whole` that is shown (its `keys` state value > 0.01; objects without a key are always shown) must be whole or out.
 */
export function heldFaults(samples: Sample[], whole: Record<string, Rect>, keys: Record<string, string>, viewports: [number, number][] = DESKTOP, inset: Inset = DEFAULT_INSET): string[] {
  const seen = new Set<string>(), out: string[] = [];
  const same = (a: Box, b: Box): boolean => Math.abs(a.x - b.x) + Math.abs(a.y - b.y) + Math.abs(a.w - b.w) + Math.abs(a.h - b.h) < 0.5;
  for (let i = 1; i < samples.length; i++) {
    const { t, cam, show } = samples[i];
    if (!same(cam, samples[i - 1].cam) || (show.exposure ?? 1) < 0.99) continue;
    for (const [W, H] of viewports) {
      const { view } = frameView(cam, W, H, inset);
      for (const [id, r] of Object.entries(whole)) {
        const k = keys[id], tag = `${id} @ ${W}x${H}`;
        if ((k === undefined || (show[k] ?? 0) > 0.01) && cuts(view, r) && !seen.has(tag)) { seen.add(tag); out.push(`${tag} from t=${t.toFixed(1)} s`); }
      }
    }
  }
  return out;
}

/** Rect of a one-line label: text of `size` drawing units anchored at (x, y) (vertical middle), align 0 left, 0.5 centre, 1 right. */
export function labelRect(x: number, y: number, text: string, size: number, align = 0): Rect {
  const w = text.length * size * 0.72 + 12, x0 = x - align * w;
  return [x0, y - size * 0.75, x0 + w, y + size * 0.75];
}

/** Every shot in which text of `size` drawing units renders below `minPx` screen px at W × H (scale numerals must stay legible). */
export function textFaults(shots: Record<string, Box>, size: number, minPx: number, W = 1920, H = 1080, inset: Inset = DEFAULT_INSET): string[] {
  return Object.entries(shots).flatMap(([name, b]) => {
    const px = frameView(b, W, H, inset).s * size;
    return px < minPx ? [`${name} @ ${W}x${H}: ${size}-unit text is ${px.toFixed(1)} px (< ${minPx})`] : [];
  });
}

/** Desktop viewports every plate is checked at: full-screen 16:9 and a browser window with its toolbars. */
export const DESKTOP: [number, number][] = [[1366, 768], [1920, 1080], [2560, 1440], [1920, 960], [2560, 1300]];

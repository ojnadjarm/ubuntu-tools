/* The room's name board, one builder for every room kind: two server racks holding a holo screen between two rails, the room's name on it in dot letters, its floor cable, the light it throws and the outline a tap picks. */
import { lamp, rack, holo, cable, sign } from "./props.js";

/* Ink rows from one line to the next, rows of a capital letter, the largest size of one ink row, and the width of the condensed letters. */
const PITCH = 11, CAP = 9, MAX = 0.045, NARROW = 0.82;

/* Every way to keep the words in order on n lines. */
function splits(words, n) {
  if (n === 1) return [[words.join(" ")]];
  const out = [];
  for (let k = 1; k <= words.length - n + 1; k++) for (const rest of splits(words.slice(k), n - 1)) out.push([words.slice(0, k).join(" "), ...rest]);
  return out;
}

/* The name on 1 to 3 lines, the split whose letters come out largest on a w × h screen: {lines, s}, s the size of one ink row. */
export function fit(ink, name, w, h) {
  const words = name.toUpperCase().split(/\s+/).filter(Boolean);
  let best = { lines: [], s: 0 };
  for (let n = 1; n <= Math.min(3, words.length); n++) for (const lines of splits(words, n)) {
    const s = Math.min(w / (NARROW * Math.max(...lines.map((l) => ink(l).w))), h / (n * PITCH), MAX);
    if (s > best.s) best = { lines, s };
  }
  return best;
}

/* The board in the current frame, its screen facing +z: racks h tall stand w apart, the screen (w × sh) hangs at y between them; a tap on it opens `id`'s card (who = the card's id when it is not the label's). */
export function board(ctx, R, { id, who, name, w = 2.1, sh = 0.95, y = 0.45, h = 1.5 }) {
  const { B, th } = ctx, col = R.busy ? th.accent : th.second, live = R.busy > 0, x = w / 2 + 0.25, pad = 0.05, ink = col.map((c) => (c * 0.5 + 0.5) * (R.awake ? 1 : 0.85));
  rack(ctx, -x, 0, 0, { seed: id, live, h }); rack(ctx, x, 0, 0, { seed: id + "b", live, h });
  for (const ry of [y - 0.035, y + sh]) B.box(0, ry, 0.05, w, 0.035, 0.05, th.frame);
  cable(ctx, [[-x, 0.25], [-x, 0.45], [x, 0.45], [x, 0.25]]);
  holo(ctx, [-w / 2, y, 0.05], [w, 0, 0], [0, sh, 0], col, live ? 0.3 : 0.2);
  const { lines, s } = fit(ctx.ink, name, w - 2 * pad, sh - 2 * pad), yc = y + sh / 2, line = (k) => yc + ((lines.length - 1) / 2 - k) * PITCH * s;
  lines.forEach((t, k) => sign(ctx, t, [0, line(k), 0.06], [NARROW, 0, 0], [0, 1, 0], ctx.ink(t).h * s, ink, { i: 0 }));
  lamp(ctx, 0, yc, 0.5, live ? 0.34 : R.awake ? 0.22 : 0.1, 1.2, { col, halo: live ? 0.3 : 0.14 });
  const at = (px, py) => { const p = B.at(px, py, 0.06); return [p.x, p.y, p.z]; }, cap = (CAP * s) / 2;
  ctx.labels.push({ id, who, pos: at(0, yc), quad: [at(-w / 2, y), at(w / 2, y), at(w / 2, y + sh), at(-w / 2, y + sh)], r: w * 0.6, cap: [at(0, line(0) + cap), at(0, line(0) - cap)] });
}

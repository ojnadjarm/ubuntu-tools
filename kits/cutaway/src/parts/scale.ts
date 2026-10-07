import * as THREE from 'three';
import { Ink, Z } from '../ink';
import { rect } from '../geom';
import { FONT, type ColorRole } from '../tokens';
import type { Part } from './part';

/** A short text on the plate: mono caps for units and axis names, serif italic for variables (`w`, `n`). */
export function note(ink: Ink, text: string, x: number, y: number, o: { size?: number; align?: 0 | 0.5 | 1; italic?: boolean; role?: ColorRole } = {}): THREE.Mesh {
  const size = o.size ?? 14, ax = o.align ?? 0, w = text.length * size * 0.8 + 8, h = size * 1.6;
  const t = ink.text(w, h, (c, th) => {
    c.fillStyle = th[o.role ?? 'inkSoft'];
    c.font = o.italic ? `italic 400 ${size}px ${FONT.serif}` : `500 ${size}px ${FONT.mono}`;
    c.letterSpacing = o.italic ? '0px' : `${(size * 0.12).toFixed(1)}px`;
    c.textBaseline = 'middle'; c.textAlign = ax === 0 ? 'left' : ax === 1 ? 'right' : 'center';
    c.fillText(text, ax * w, h / 2);
  }, ax, 0.5);
  t.mesh.position.set(x, y, Z.text);
  return t.mesh;
}

/** Engraved linear scale from (x0, y0) along x (or along y when `vertical`): major ticks with mono numerals, minor ticks between. */
export class Scale implements Part {
  readonly root = new THREE.Group();
  constructor(ink: Ink, x0: number, y0: number, readonly length: number, readonly min: number, readonly max: number,
    o: { vertical?: boolean; major?: number; minor?: number; side?: 1 | -1; format?: (v: number) => string; size?: number } = {}) {
    const major = o.major ?? 1, minor = o.minor ?? major / 4, side = o.side ?? -1, size = o.size ?? 14, vert = !!o.vertical;
    const fmt = o.format ?? ((v: number) => (min < 0 ? (v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0') : String(v)));
    const at = (v: number): number => ((v - min) / (max - min)) * length;
    const P = (u: number, n: number): [number, number] => (vert ? [x0 + n * side, y0 + u] : [x0 + u, y0 + n * side]);
    const hair: number[] = [...P(0, 0), ...P(length, 0)], thin: number[] = [], labels: [string, number][] = [];
    for (let v = Math.ceil(min / minor) * minor; v <= max + 1e-6; v += minor) {
      const isMajor = Math.abs(v / major - Math.round(v / major)) < 1e-6, half = Math.abs((2 * v) / major - Math.round((2 * v) / major)) < 1e-6;
      (isMajor ? thin : hair).push(...P(at(v), 0), ...P(at(v), isMajor ? 14 : half ? 9 : 5));
      if (isMajor) labels.push([fmt(Math.round(v * 1000) / 1000), at(v)]);
    }
    this.root.add(ink.segs(hair, ink.line('ink', 'hair'), Z.line), ink.segs(thin, ink.line('ink', 'thin'), Z.line));
    const pad = size * 3, w = vert ? size * 4 : length + 2 * pad, h = vert ? length + 2 * pad : size * 1.6;
    const t = ink.text(w, h, (c, th) => {
      c.fillStyle = th.inkSoft; c.font = `500 ${size}px ${FONT.mono}`; c.textBaseline = 'middle';
      c.textAlign = vert ? (side > 0 ? 'left' : 'right') : 'center';
      for (const [s, u] of labels) vert ? c.fillText(s, side > 0 ? 0 : w, h - pad - u) : c.fillText(s, pad + u, h / 2);
    }, vert ? (side > 0 ? 0 : 1) : 0, 0);
    const gap = 14 + size * 0.5;
    if (vert) t.mesh.position.set(x0 + side * (gap + 4), y0 - pad, Z.text);
    else t.mesh.position.set(x0 - pad, y0 + side * (18 + size * 0.7) - h / 2, Z.text);
    this.root.add(t.mesh);
  }
}

/** Engineering graph paper: hairline minor grid, heavier major grid, a thin frame with a hairline outer rule. */
export class GraphPaper implements Part {
  readonly root = new THREE.Group();
  constructor(ink: Ink, readonly x0: number, readonly y0: number, readonly x1: number, readonly y1: number, cols: number, rows: number, sub = 2) {
    const fine: number[] = [], grid: number[] = [];
    this.root.add(ink.shape([x0, y0, x1, y0, x1, y1, x0, y1], ink.fill('paper'), Z.fill));
    for (let i = 0; i <= cols * sub; i++) { const x = x0 + ((x1 - x0) * i) / (cols * sub); (i % sub ? fine : grid).push(x, y0, x, y1); }
    for (let j = 0; j <= rows * sub; j++) { const y = y0 + ((y1 - y0) * j) / (rows * sub); (j % sub ? fine : grid).push(x0, y, x1, y); }
    this.root.add(ink.segs(fine, ink.line('hatch', 0.45), Z.hatch), ink.segs(grid, ink.line('hatch', 'hair'), Z.hatch + 0.1));
    this.root.add(ink.segs(rect(x0, y0, x1, y1), ink.line('ink', 'thin'), Z.line), ink.segs(rect(x0 - 6, y0 - 6, x1 + 6, y1 + 6), ink.line('ink', 'hair'), Z.line));
  }
}

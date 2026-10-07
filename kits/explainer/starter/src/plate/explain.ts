import * as THREE from 'three';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import type { Explained } from 'explainer-kit';
import { Ink, Z, FONT, TextPlate, arcPts, polyline, type Theme } from 'cutaway-kit';
import type { SpotSpec } from '../units/a02/layout';

/** The stage as the note needs it: screen size, scale and the two projections. */
interface Screen { W: number; H: number; s: number; toScreen(x: number, y: number): [number, number]; toWorld(px: number, py: number): [number, number] }
type Rect = { x: number; y: number; w: number; h: number };

const W = 336, PAD = 16, TOP = 36, BOTTOM = 172, GAP = 44, CLOSE = 40, FOOT = 34;
const clock = (t: number): string => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
const inside = (r: Rect | null, x: number, y: number): boolean => !!r && x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h;

/** Lines of `text` that fit `w` px in the context's current font; a newline always breaks. */
function wrap(g: CanvasRenderingContext2D, text: string, w: number): string[] {
  if (text.includes('\n')) return text.split('\n').flatMap((t) => wrap(g, t, w));
  const out: string[] = [];
  for (const word of text.split(/\s+/)) {
    const last = out.at(-1);
    if (last !== undefined && g.measureText(`${last} ${word}`).width <= w) out[out.length - 1] = `${last} ${word}`; else out.push(word);
  }
  return out;
}

/** What the note says, laid out once per change of text. */
interface Card { title: string; body: string[]; now: string[]; foot: string | null; h: number }
const BODY = `400 17px ${FONT.serif}`, NOW = `500 14px ${FONT.mono}`;
const measure = document.createElement('canvas').getContext('2d')!;

function card(c: Explained): Card {
  const locked = c.chapter ? `Explained in chapter ${c.chapter.numeral}, ${c.chapter.label}.` : 'Explained in your turn.';
  measure.font = BODY;
  const body = wrap(measure, c.available ? c.what.replace(/^./, (m) => m.toUpperCase()) + '.' : locked, W - 2 * PAD);
  const foot = c.available && c.said ? (Number.isFinite(c.saidAt) ? `SAID AT ${clock(c.saidAt)} ▸ HEAR IT` : 'SAID IN YOUR TURN ▸ HEAR IT') : null;
  measure.font = NOW;
  const now = c.available && c.now ? wrap(measure, c.now, W - 2 * PAD) : [];
  const h = PAD + 22 + 8 + body.length * 24 + (now.length ? 8 + now.length * 22 : 0) + (foot ? FOOT + 6 : 4) + PAD - 6;
  return { title: c.available ? c.title.toUpperCase() : 'NOT YET', body, now, foot, h };
}

/** The callout of one part, drawn on the plate: a dot on the part, a leader, and a screen-constant note (word, gloss, the numbers now, "hear it"). */
export class ExplainNote {
  readonly root = new THREE.Group();
  private dot: THREE.Mesh;
  private leader: LineSegments2;
  private plate: TextPlate | null = null;
  private c: Explained | null = null;
  private card: Card | null = null;
  private key = '';
  private at: Rect | null = null;
  constructor(private ink: Ink) {
    this.dot = ink.disc(0, 0, 4.2, ink.fill('ink'), Z.callout + 0.2, 20);
    this.leader = ink.segs([], ink.line('ink', 'thin'), Z.callout + 0.1);
    this.root.add(this.dot, this.leader);
    this.root.visible = false;
  }

  set(c: Explained | null): void {
    this.c = c;
    this.root.visible = !!c;
    if (!c) { this.at = null; return; }
    const cd = card(c), key = JSON.stringify(cd);
    if (key === this.key) return;
    this.key = key; this.card = cd;
    if (this.plate) { this.root.remove(this.plate.mesh); this.plate.mesh.geometry.dispose(); this.plate.mat.map?.dispose(); this.plate.mat.dispose(); }
    this.plate = new TextPlate(W, cd.h, (g, th) => this.paint(g, th, cd), 0, 1);
    this.plate.mesh.position.z = Z.text + 1;
    this.plate.redraw(Math.min(2, devicePixelRatio), this.ink.theme);
    this.root.add(this.plate.mesh);
  }

  private paint(g: CanvasRenderingContext2D, th: Theme, cd: Card): void {
    g.fillStyle = th.paper; g.fillRect(0, 0, W, cd.h);
    g.strokeStyle = th.ink; g.lineWidth = 1.25; g.strokeRect(0.6, 0.6, W - 1.2, cd.h - 1.2);
    g.fillStyle = th.ink; g.textBaseline = 'alphabetic';
    g.font = `600 15px ${FONT.label}`; g.letterSpacing = '1.2px'; g.fillText(cd.title, PAD, PAD + 16);
    g.font = `400 22px ${FONT.label}`; g.letterSpacing = '0px'; g.textAlign = 'center'; g.fillText('×', W - CLOSE / 2, PAD + 16); g.textAlign = 'left';
    let y = PAD + 22 + 8;
    g.font = BODY;
    for (const line of cd.body) { y += 24; g.fillText(line, PAD, y - 6); }
    if (cd.now.length) { y += 8; g.font = NOW; for (const line of cd.now) { y += 22; g.fillText(line, PAD, y - 6); } }
    if (!cd.foot) return;
    y += 6;
    g.strokeStyle = th.inkSoft; g.lineWidth = 0.7; g.beginPath(); g.moveTo(PAD, y); g.lineTo(W - PAD, y); g.stroke();
    g.fillStyle = th.blue; g.font = `500 12px ${FONT.mono}`; g.letterSpacing = '1.4px'; g.fillText(cd.foot, PAD, y + 22);
  }

  /** Place the note beside its dot, inside the drawing area between the top and the bar, and draw the leader to its nearest edge. */
  frame(st: Screen): void {
    const c = this.c, cd = this.card;
    if (!c || !cd || !this.plate) return;
    const [dx, dy] = c.dot ? st.toScreen(c.dot[0], c.dot[1]) : [st.W - W - 24, TOP + cd.h];
    const right = dx + GAP + W <= st.W - 16 || dx - GAP - W < 16;
    const x = Math.min(st.W - W - 16, Math.max(16, right ? dx + GAP : dx - GAP - W));
    const y = Math.min(st.H - BOTTOM - cd.h, Math.max(TOP, dy - cd.h - GAP / 2));
    this.at = { x, y, w: W, h: cd.h };
    const [wx, wy] = st.toWorld(x, y);
    this.plate.mesh.position.set(wx, wy, Z.text + 1);
    this.plate.mesh.scale.setScalar(1 / st.s);
    this.dot.visible = !!c.dot;
    if (!c.dot) { this.ink.setSegs(this.leader, []); return; }
    this.dot.position.set(c.dot[0], c.dot[1], Z.callout + 0.2);
    const ex = Math.min(x + W, Math.max(x, dx)), ey = Math.min(y + cd.h, Math.max(y, dy));
    const [lx, ly] = st.toWorld(ex, ey);
    this.ink.setSegs(this.leader, inside(this.at, dx, dy) ? [] : [c.dot[0], c.dot[1], lx, ly]);
  }

  /** What of the note is under screen point (px, py). */
  hit(px: number, py: number): 'hear' | 'close' | 'inside' | null {
    const r = this.at;
    if (!r || !inside(r, px, py)) return null;
    if (px >= r.x + r.w - CLOSE && py <= r.y + CLOSE) return 'close';
    if (this.card?.foot && py >= r.y + r.h - FOOT - PAD) return 'hear';
    return 'inside';
  }
}

/** A dashed outline around one part (hover, focus, a parts-list row). */
export class PartLight {
  readonly root = new THREE.Group();
  private lines = new Map<string, LineSegments2>();
  constructor(ink: Ink, spots: Record<string, SpotSpec>) {
    const mat = ink.line('ink', 'thin', { dash: [10, 7] });
    for (const [id, s] of Object.entries(spots)) {
      const segs = [
        ...(s.discs ?? []).flatMap(([cx, cy, r]) => polyline(arcPts(cx, cy, r + 8, 0, Math.PI * 2, 72), true)),
        ...(s.boxes ?? []).flatMap(([a, b, c, e]) => polyline([a - 8, b - 8, c + 8, b - 8, c + 8, e + 8, a - 8, e + 8], true)),
      ];
      const l = ink.segs(segs, mat, Z.callout); l.visible = false;
      this.lines.set(id, l); this.root.add(l);
    }
  }
  set(part: string | null): void { for (const [id, l] of this.lines) l.visible = id === part; }
}

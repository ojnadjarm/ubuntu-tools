import * as THREE from 'three';
import { Ink, Z } from '../ink';
import { rect } from '../geom';
import { FONT, TYPE } from '../tokens';
import { TITLE, titleRect, type Rect } from '../framing';
import type { Part } from './part';

/** What the title block says; `legend` names the numbered balloons in order; `drawn`/`approved` add a signature strip. */
export interface TitleSpec { plate: string; title: string; ref: string; scale: string; sheet: string; legend: string[]; drawn?: string; approved?: string }

const BW = TITLE.w, BH = TITLE.h, M = TITLE.margin;

/** True when the title block carries the DRAWN / APPROVED signature strip. */
export const signed = (t: TitleSpec): boolean => Boolean(t.drawn || t.approved);

/** The drawing sheet: double border, zone marks and the title block in the bottom-right corner. */
export class Sheet implements Part {
  readonly root = new THREE.Group();
  /** Where the title block sits: every resting shot must show it whole or not at all (see framing.ts). */
  readonly titleRect: Rect;
  constructor(ink: Ink, box: Rect, title: TitleSpec) {
    const g = this.root, [x0, y0, x1, y1] = box, m = M;
    g.add(ink.segs(rect(x0, y0, x1, y1), ink.line('ink', 'med'), Z.line));
    g.add(ink.segs(rect(x0 + m, y0 + m, x1 - m, y1 - m), ink.line('ink', 'hair'), Z.line));
    const zt: number[] = [], cols = 8, rows = 6;
    for (let i = 1; i < cols; i++) { const x = x0 + ((x1 - x0) * i) / cols; zt.push(x, y0, x, y0 + m, x, y1, x, y1 - m); }
    for (let i = 1; i < rows; i++) { const y = y0 + ((y1 - y0) * i) / rows; zt.push(x0, y, x0 + m, y, x1, y, x1 - m, y); }
    g.add(ink.segs(zt, ink.line('ink', 'hair'), Z.line));
    const zone = (s: string, x: number, y: number): void => {
      const t = ink.text(20, 16, (c, th) => { c.fillStyle = th.inkSoft; c.font = `500 ${TYPE.zone}px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(s, 10, 8); }, 0.5, 0.5);
      t.mesh.position.set(x, y, Z.text); g.add(t.mesh);
    };
    for (let i = 0; i < cols; i++) { const x = x0 + ((x1 - x0) * (i + 0.5)) / cols; zone(String(cols - i), x, y0 + m / 2); zone(String(cols - i), x, y1 - m / 2); }
    for (let i = 0; i < rows; i++) { const y = y0 + ((y1 - y0) * (i + 0.5)) / rows; zone('ABCDEF'[i], x0 + m / 2, y); zone('ABCDEF'[i], x1 - m / 2, y); }
    this.titleRect = titleRect(box, signed(title));
    const block = new TitleBlock(ink, this.titleRect[0], this.titleRect[1], title);
    g.add(block.root);
  }
}

/** Engineering title block: plate number, title, reference, scale, sheet count, the balloon legend and the optional signatures. */
export class TitleBlock implements Part {
  readonly root = new THREE.Group();
  readonly rect: Rect;
  constructor(ink: Ink, bx: number, by: number, t: TitleSpec) {
    const g = this.root, sh = signed(t) ? TITLE.sign : 0, H = BH + sh;
    this.rect = [bx, by, bx + BW, by + H];
    g.add(ink.shape([bx, by, bx + BW, by, bx + BW, by + H, bx, by + H], ink.fill('paper'), Z.fill));
    g.add(ink.segs(rect(bx, by, bx + BW, by + H), ink.line('ink', 'thin'), Z.line));
    const txt = ink.text(BW, H, (c, th) => {
      c.strokeStyle = th.ink; c.lineWidth = 1;
      c.beginPath(); c.moveTo(0, 40); c.lineTo(BW, 40); c.moveTo(0, 112); c.lineTo(BW, 112); c.moveTo(380, 40); c.lineTo(380, 112);
      if (sh) { c.moveTo(0, BH); c.lineTo(BW, BH); c.moveTo(BW / 2, BH); c.lineTo(BW / 2, H); }
      c.stroke();
      c.textBaseline = 'alphabetic';
      c.fillStyle = th.inkSoft; c.font = `italic 400 17px ${FONT.serif}`; c.fillText(t.plate, 16, 27);
      c.font = `500 12px ${FONT.mono}`; c.textAlign = 'right'; c.fillText(t.ref, BW - 16, 26);
      c.textAlign = 'left'; c.fillText(t.scale, 396, 68); c.fillText(t.sheet, 396, 92);
      c.fillStyle = th.ink; c.font = `600 ${TYPE.title}px ${FONT.label}`; c.letterSpacing = '4px'; c.fillText(t.title, 16, 92);
      c.letterSpacing = '0px'; c.font = `400 15px ${FONT.label}`;
      t.legend.forEach((s, i) => c.fillText(`${i + 1}  ${s}`, 16 + (i % 3) * 184, 138 + Math.floor(i / 3) * 24));
      if (!sh) return;
      ([['DRAWN', t.drawn], ['APPROVED', t.approved]] as const).forEach(([k, v], i) => {
        const x = 16 + (i * BW) / 2;
        c.fillStyle = th.inkSoft; c.font = `500 11px ${FONT.mono}`; c.letterSpacing = '1.5px'; c.fillText(k, x, BH + 25);
        c.fillStyle = th.ink; c.font = `italic 400 19px ${FONT.serif}`; c.letterSpacing = '0px'; c.fillText(v ?? '', x + 88, BH + 27);
      });
    }, 0, 0);
    txt.mesh.position.set(bx, by, Z.text);
    g.add(txt.mesh);
  }
}

/** Figure caption in the plate's serif italic ("Fig. 1."). */
export function caption(ink: Ink, text: string, x: number, y: number): THREE.Mesh {
  const t = ink.text(420, 30, (c, th) => { c.fillStyle = th.inkSoft; c.font = `italic 400 ${TYPE.caption}px ${FONT.serif}`; c.textBaseline = 'middle'; c.fillText(text, 0, 15); }, 0, 0.5);
  t.mesh.position.set(x, y, Z.text);
  return t.mesh;
}

/** Disc of radius 3 whose vertex alpha rises from 0 inside r = 0.35 to 1 at r = 1 (smooth, no texture banding). */
function washGeometry(): THREE.BufferGeometry {
  const radii = [0, 0.35, 0.5, 0.65, 0.8, 1, 3], seg = 72, pos: number[] = [], col: number[] = [], idx: number[] = [];
  radii.forEach((r) => {
    const a = THREE.MathUtils.smoothstep(r, 0.35, 1);
    for (let i = 0; i < seg; i++) { const t = (i / seg) * Math.PI * 2; pos.push(Math.cos(t) * r, Math.sin(t) * r, 0); col.push(1, 1, 1, a); }
  });
  for (let k = 0; k < radii.length - 1; k++) for (let i = 0; i < seg; i++) {
    const a = k * seg + i, b = k * seg + ((i + 1) % seg), c = a + seg, d = b + seg;
    idx.push(a, c, b, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 4));
  g.setIndex(idx);
  return g;
}

/** The narrator's pointer: the sheet darkens slightly away from the part being named, like paper under a desk lamp. */
export class FocusLamp implements Part {
  readonly root = new THREE.Group();
  private mat: THREE.MeshBasicMaterial;
  private mesh: THREE.Mesh;
  constructor(ink: Ink) {
    this.mat = ink.fill('vignette', { own: true, opacity: 0 });
    this.mat.vertexColors = true;
    this.mesh = new THREE.Mesh(washGeometry(), this.mat);
    this.mesh.position.z = Z.focus;
    this.root.add(this.mesh);
  }
  set(x: number, y: number, on: number, span: number): void {
    this.mesh.position.set(x, y, Z.focus);
    this.mesh.scale.setScalar(span * 0.6);
    this.mat.opacity = 0.11 * on;
  }
}

/** Paper veil over everything: the plate emerges from blank paper as exposure goes 0 → 1. */
export class Veil implements Part {
  readonly root = new THREE.Group();
  private mat: THREE.MeshBasicMaterial;
  private mesh: THREE.Mesh;
  constructor(ink: Ink) {
    this.mat = ink.fill('paper', { own: true, opacity: 1 });
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), this.mat);
    this.root.add(this.mesh);
  }
  set(x: number, y: number, w: number, h: number, exposure: number): void {
    this.mesh.position.set(x, y, Z.veil);
    this.mesh.scale.set(w * 3, h * 3, 1);
    this.mat.opacity = 1 - exposure;
    this.mesh.visible = exposure < 0.999;
  }
}

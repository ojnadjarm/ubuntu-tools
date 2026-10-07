import { centre, dist, edgePoint, overlaps, segOf, within, type Shape } from './shapes';

/**
 * What a drawn thing is to the layout. Fixed kinds are drawn where they are (`part`, `container`, `figure`, `label`, `cue`); the placer
 * moves the others (`control`, `value`, `marker`) to their first clear slot. A `marker` is a numbered badge with a leader to its part's
 * edge. A `cue` (a hint or move arrow) may cross anything, but only on top of it: it is judged by draw layer, not by distance.
 */
export type Kind = 'part' | 'container' | 'figure' | 'label' | 'control' | 'value' | 'marker' | 'cue';
const MOVABLE: Kind[] = ['control', 'value', 'marker'];
const ITEM: Kind[] = ['label', ...MOVABLE];

export interface Entity {
  id: string; kind: Kind;
  /** Scenes the entity can be drawn in; two entities are checked against each other only when they share one. */
  scenes: string[];
  /** Fixed: its outline. */
  shapes?: Shape[];
  /** A part: the outline its markers' leaders end on (default its first shape). */
  body?: Shape;
  /** A marker or value: the part it names (a marker's leader ends on that part's `body`). */
  part?: string;
  /** Parts this one is drawn on or in: its value boxes may sit inside them, its markers' leaders may cross them. */
  host?: string[];
  /** Movable: its outline centred on 0, 0, and the centres to try, in preference order. */
  form?: Shape;
  slots?: [number, number][];
  /** Draw layer (higher covers lower); a `cue` under an item with a layer at or above its own is a fault. Unset: not judged by layer. */
  z?: number;
  /** A frame it must not be cut by: wholly inside `inner` (the clear zone) or wholly clear of `outer` (the frame's outside edge). */
  clip?: { inner: Shape; outer: Shape };
}
/** A placed entity: its outline where it is drawn, and a marker's leader (part edge → badge rim). */
export interface Item extends Entity { shapes: Shape[]; at?: [number, number]; slot?: number; leader?: Extract<Shape, { k: 'seg' }> }
/** Clear distances in drawing units: to a part or figure outline, between two items, around a control, beside a leader, and from a value box to an outline (default `toPart`). */
export interface Rules { toPart: number; between: number; clear: number; leader: number; value?: number }
export const RULES: Rules = { toPart: 12, between: 20, clear: 40, leader: 4 };

const moveTo = (f: Shape, [x, y]: [number, number]): Shape =>
  f.k === 'disc' ? { ...f, x, y } : f.k === 'box' ? { ...f, x0: f.x0 + x, x1: f.x1 + x, y0: f.y0 + y, y1: f.y1 + y } : { ...f, x0: f.x0 + x, x1: f.x1 + x, y0: f.y0 + y, y1: f.y1 + y };
const shares = (a: Entity, b: Entity): boolean => a.scenes.some((s) => b.scenes.includes(s));
const mine = (a: Entity, b: Entity): boolean => !!a.part && (b.id === a.part || (a.host ?? []).includes(b.id));
const minDist = (as: Shape[], bs: Shape[]): number => Math.min(...as.flatMap((a) => bs.map((b) => dist(a, b))));
const radius = (f: Shape): number => (f.k === 'disc' ? f.r : 0);

/** Put a movable entity at `at`: its outline, and for a marker the leader from its part's edge to its rim. */
export function put(e: Entity, at: [number, number], parts: Map<string, Entity>, slot = 0): Item {
  const shape = moveTo(e.form!, at), it: Item = { ...e, shapes: [shape], at, slot };
  const body = e.part ? parts.get(e.part) : undefined, b = body?.body ?? body?.shapes?.[0];
  if (e.kind === 'marker' && b) {
    const [ex, ey] = edgePoint(b, at), l = Math.hypot(at[0] - ex, at[1] - ey) || 1, r = radius(e.form!);
    it.leader = segOf(ex, ey, at[0] - ((at[0] - ex) / l) * r, at[1] - ((at[1] - ey) / l) * r) as Item['leader'];
  }
  return it;
}

/** Every broken rule between two items that share a scene, as readable faults ("marker 8 × value sum: 9 < 20"). */
export function pairFaults(a: Item, b: Item, r: Rules = RULES): string[] {
  if (a === b || !shares(a, b)) return [];
  if (a.kind === 'cue' || b.kind === 'cue') return underFaults(a, b);
  if (!ITEM.includes(a.kind) && !ITEM.includes(b.kind)) return [];
  const out: string[] = [], name = (e: Entity): string => `${e.kind} ${e.id}`;
  for (const [x, y] of [[a, b], [b, a]] as [Item, Item][]) {
    if (!x.leader || y.kind === 'container' || mine(x, y)) continue;
    if (y.shapes.some((s) => overlaps(x.leader!, s, r.leader))) out.push(`${name(x)} leader crosses ${name(y)}`);
  }
  if (!ITEM.includes(a.kind)) [a, b] = [b, a];
  if (b.kind === 'container') {
    if (a.shapes.every((s) => within(s, b.shapes[0]))) return out;
    const d = minDist(a.shapes, edges(b.shapes[0]));
    if (d < r.toPart) out.push(`${name(a)} straddles ${name(b)}: ${d.toFixed(0)} < ${r.toPart}`);
    return out;
  }
  if (a.kind === 'value' && (a.host ?? []).includes(b.id) && a.shapes.every((s) => b.shapes.some((h) => within(s, h)))) return out;
  const gap = a.kind === 'control' || b.kind === 'control' ? r.clear : ITEM.includes(b.kind) ? r.between : a.kind === 'value' ? r.value ?? r.toPart : r.toPart;
  const d = minDist(a.shapes, b.shapes);
  if (d < gap) out.push(`${name(a)} × ${name(b)}: ${d.toFixed(0)} < ${gap}`);
  return out;
}
/** A cue drawn under what it crosses: the other item has a layer at or above the cue's and their outlines touch. */
function underFaults(a: Item, b: Item): string[] {
  const [c, o] = a.kind === 'cue' ? [a, b] : [b, a];
  if (o.kind === 'container' || o.kind === 'cue' || c.z === undefined || o.z === undefined || o.z < c.z) return [];
  return c.shapes.some((s) => o.shapes.some((t) => overlaps(s, t))) ? [`cue ${c.id} under ${o.kind} ${o.id}`] : [];
}
/** An item cut by its frame: neither wholly inside the clear zone nor wholly clear of the frame. */
export const clipped = (it: Item): boolean => !!it.clip && !it.shapes.every((s) => within(s, it.clip!.inner)) && it.shapes.some((s) => overlaps(s, it.clip!.outer));

/** A container's outline as its edge: four segments (a disc or a segment stands for itself). */
const edges = (c: Shape): Shape[] => (c.k === 'box'
  ? [segOf(c.x0, c.y0, c.x1, c.y0), segOf(c.x1, c.y0, c.x1, c.y1), segOf(c.x1, c.y1, c.x0, c.y1), segOf(c.x0, c.y1, c.x0, c.y0)] : [c]);

/** A leader must start on its part's edge: the distance from its start to the part's outline, 0 when it does. */
export function offEdge(it: Item, parts: Map<string, Entity>): number {
  const p = it.part ? parts.get(it.part) : undefined, b = p?.body ?? p?.shapes?.[0];
  if (!it.leader || !b) return 0;
  const { x0: x, y0: y } = it.leader;
  if (b.k === 'disc') return Math.abs(Math.hypot(x - b.x, y - b.y) - b.r);
  if (b.k === 'box') return Math.min(Math.abs(x - b.x0), Math.abs(x - b.x1), Math.abs(y - b.y0), Math.abs(y - b.y1)) + dist(segOf(x, y, x, y), b);
  return 0;
}

/** The single rule set: every fault in a laid-out drawing (placer, node test and browser test all use it). */
export function layoutFaults(items: Item[], r: Rules = RULES): string[] {
  const out: string[] = [], parts = new Map(items.filter((e) => e.kind === 'part').map((e) => [e.id, e as Entity]));
  items.forEach((a, i) => { for (const b of items.slice(i + 1)) out.push(...pairFaults(a, b, r)); });
  for (const it of items) if (offEdge(it, parts) > 0.5) out.push(`marker ${it.id} leader does not end on ${it.part}'s edge`);
  for (const it of items) if (clipped(it)) out.push(`${it.kind} ${it.id} clipped by its frame`);
  return out;
}

/**
 * Greedy placement in priority order (controls, then values, then markers; entity order inside a class): each movable takes its first
 * slot that breaks no rule against what is already placed. Deterministic. An item no slot fits stays on its first slot and is a fault.
 */
export function place(entities: Entity[], r: Rules = RULES): { placed: Item[]; faults: string[] } {
  const parts = new Map(entities.filter((e) => e.kind === 'part').map((e) => [e.id, e]));
  const placed: Item[] = entities.filter((e) => !MOVABLE.includes(e.kind)).map((e) => ({ ...e, shapes: e.shapes ?? [] }));
  const faults: string[] = [];
  for (const kind of MOVABLE) for (const e of entities.filter((x) => x.kind === kind)) {
    let best: Item | null = null, why: string[] = [];
    for (const [i, at] of (e.slots ?? []).entries()) {
      const it = put(e, at, parts, i), f = placed.flatMap((p) => pairFaults(it, p, r));
      if (!f.length) { best = it; break; }
      if (i === 0) { best = it; why = f; }
    }
    if (!best) { faults.push(`${e.kind} ${e.id}: no slots`); continue; }
    if (best.slot === 0 && why.length) faults.push(`${e.kind} ${e.id}: no clear slot (${why[0]})`);
    placed.push(best);
  }
  return { placed, faults };
}

/** Marker slots round a part: rays from its centre at the authored direction first, then by angular distance, at each leader length. */
export function ring(body: Shape, toward: [number, number], r: number, lengths = [18, 30, 44, 60, 80], step = 12): [number, number][] {
  const [cx, cy] = centre(body), a0 = Math.atan2(toward[1] - cy, toward[0] - cx), out: { at: [number, number]; cost: number }[] = [];
  for (let k = 0; k <= 180 / step; k++) for (const s of k ? [1, -1] : [1]) lengths.forEach((len, j) => {
    const a = a0 + (s * k * step * Math.PI) / 180, [ex, ey] = edgePoint(body, [cx + Math.cos(a), cy + Math.sin(a)]);
    out.push({ at: [ex + Math.cos(a) * (len + r), ey + Math.sin(a) * (len + r)], cost: k + j * 1.5 });
  });
  return out.sort((p, q) => p.cost - q.cost).map((p) => p.at);
}

/** A control's centre beside a box anchor: on `side`, aligned to its start, middle or end, `margin` clear of it. */
export function beside(anchor: Shape, side: 'below' | 'above' | 'left' | 'right', align: 'start' | 'middle' | 'end', margin: number, [w, h]: [number, number]): [number, number] {
  if (anchor.k !== 'box') throw new Error('beside needs a box');
  const f = { start: 0, middle: 0.5, end: 1 }[align];
  if (side === 'below' || side === 'above') {
    const x = anchor.x0 + w / 2 + (anchor.x1 - anchor.x0 - w) * f;
    return [x, side === 'below' ? anchor.y0 - margin - h / 2 : anchor.y1 + margin + h / 2];
  }
  const y = anchor.y0 + h / 2 + (anchor.y1 - anchor.y0 - h) * f;
  return [side === 'left' ? anchor.x0 - margin - w / 2 : anchor.x1 + margin + w / 2, y];
}

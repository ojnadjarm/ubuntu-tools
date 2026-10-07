import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boxOf, discOf, segOf, dist, overlaps, segHits, edgePoint, within, mapShape } from '../src/place/shapes';
import { place, layoutFaults, clipped, ring, beside, put, RULES, type Entity, type Item } from '../src/place/place';
import { MarkerRouter, partMarkers } from '../src/play/markers';

const part = (id: string, shape = boxOf(0, 0, 100, 100), scenes = ['a']): Entity => ({ id, kind: 'part', scenes, shapes: [shape] });

test('shapes: distances, overlaps, leader crossings, edge points and containment', () => {
  assert.equal(dist(boxOf(0, 0, 10, 10), boxOf(20, 0, 30, 10)), 10);
  assert.equal(dist(discOf(0, 0, 5), discOf(20, 0, 5)), 10);
  assert.equal(dist(discOf(0, 0, 5), boxOf(10, -5, 20, 5)), 5);
  assert.ok(overlaps(boxOf(0, 0, 10, 10), boxOf(5, 5, 15, 15)));
  assert.ok(overlaps(boxOf(0, 0, 10, 10), boxOf(15, 0, 20, 10), 6) && !overlaps(boxOf(0, 0, 10, 10), boxOf(15, 0, 20, 10), 4));
  assert.ok(segHits(segOf(-10, 5, 30, 5), boxOf(0, 0, 10, 10)), 'Liang-Barsky: a segment through a box');
  assert.ok(!segHits(segOf(-10, 20, 30, 20), boxOf(0, 0, 10, 10)));
  assert.ok(segHits(segOf(-10, 0, 10, 0), discOf(0, 3, 4)));
  assert.deepEqual(edgePoint(boxOf(0, 0, 10, 10), [5, 100]), [5, 10]);
  assert.deepEqual(edgePoint(discOf(0, 0, 10), [0, -50]), [0, -10]);
  assert.ok(within(boxOf(2, 2, 4, 4), boxOf(0, 0, 10, 10)) && !within(boxOf(8, 8, 12, 12), boxOf(0, 0, 10, 10)));
  assert.deepEqual(mapShape(discOf(1, 2, 3), (x, y) => [x * 2, -y * 2], 2), discOf(2, -4, 6));
});

test('place: the first clear slot wins, in priority order (controls, values, markers), only against what shares a scene; an unplaceable item is a fault', () => {
  const val: Entity = { id: 'v', kind: 'value', scenes: ['a'], form: boxOf(-10, -10, 10, 10), slots: [[50, 50], [150, 50]] };
  const ctl: Entity = { id: 'c', kind: 'control', scenes: ['a'], form: boxOf(-10, -10, 10, 10), slots: [[160, 50], [300, 50]] };
  const far: Entity = { id: 'f', kind: 'value', scenes: ['b'], form: boxOf(-10, -10, 10, 10), slots: [[50, 50]] };
  const { placed, faults } = place([part('p'), val, ctl, far]);
  const at = (id: string) => placed.find((e) => e.id === id)!.at;
  assert.deepEqual(at('c'), [160, 50], 'the control goes first');
  assert.deepEqual(at('v'), [50, 50], 'no clear slot: it stays on its first');
  assert.ok(faults.length > 0, 'the value has no slot clear of both the part and the control');
  assert.match(faults[0], /value v: no clear slot/);
  assert.deepEqual(at('f'), [50, 50], 'scene b shares nothing with the part');
  const ok = place([part('p'), { ...val, slots: [[50, 50], [160, 50]] }]);
  assert.deepEqual([ok.placed.at(-1)!.at, ok.faults], [[160, 50], []]);
});

test('layoutFaults: an overlap, a short gap, a foreign leader crossing, a straddled container edge; a marker leader ends on its own part', () => {
  const p = part('p'), q = part('q', boxOf(200, 0, 300, 100));
  const m: Entity = { id: '1', kind: 'marker', part: 'p', scenes: ['a'], form: discOf(0, 0, 15) };
  const parts = new Map([['p', p], ['q', q]]);
  const good = put(m, [50, 140], parts);
  assert.deepEqual(layoutFaults([{ ...p, shapes: p.shapes! }, { ...q, shapes: q.shapes! }, good]), []);
  assert.ok(Math.abs(good.leader!.y0 - 100) < 1e-9, 'the leader starts on the part edge');
  const across = put(m, [350, 50], parts);
  assert.ok(layoutFaults([{ ...p, shapes: p.shapes! }, { ...q, shapes: q.shapes! }, across]).some((f) => /marker 1 leader crosses part q/.test(f)));
  const v: Entity = { id: 'v', kind: 'value', scenes: ['a'], form: boxOf(-10, -10, 10, 10) };
  assert.ok(layoutFaults([{ ...p, shapes: p.shapes! }, put(v, [105, 50], parts)]).some((f) => /value v × part p: \d+ < 12/.test(f)));
  assert.deepEqual(layoutFaults([{ ...p, shapes: p.shapes! }, put(v, [115, 50], parts)], { ...RULES, value: 4 }), [], 'a unit may let value boxes sit closer to outlines');
  const c: Entity = { id: 'case', kind: 'container', scenes: ['a'], shapes: [boxOf(-200, -200, 400, 300)] };
  assert.ok(layoutFaults([{ ...c, shapes: c.shapes! }, put(v, [400, 0], parts)]).some((f) => /straddles container case/.test(f)));
  assert.deepEqual(layoutFaults([{ ...c, shapes: c.shapes! }, put(v, [300, 250], parts)]), []);
});

test('layoutFaults: a cue (hint arrow) is judged by layer, never by distance; a framed item is cut when it straddles its clear zone', () => {
  const box: Item = { id: 'v', kind: 'value', scenes: ['a'], shapes: [boxOf(0, 0, 40, 20)], z: 9 };
  const arc = (z: number): Item => ({ id: 'arc', kind: 'cue', scenes: ['a'], shapes: [segOf(-20, 10, 60, 10)], z });
  assert.deepEqual(layoutFaults([box, arc(8)]), ['cue arc under value v'], 'the arrow drawn under the value box');
  assert.deepEqual(layoutFaults([box, arc(10)]), [], 'on top it may cross');
  assert.deepEqual(layoutFaults([{ ...box, z: undefined }, arc(8)]), [], 'an item with no layer is not judged');
  assert.deepEqual(layoutFaults([box, { ...arc(8), shapes: [segOf(-20, 60, 60, 60)] }]), [], 'no crossing, no fault');
  const clip = { inner: boxOf(-100, -100, 100, 100), outer: boxOf(-130, -130, 130, 130) };
  const at = (x: number): Item => ({ id: 'pen', kind: 'figure', scenes: ['a'], shapes: [boxOf(x, 0, x + 20, 10)], clip });
  assert.deepEqual(layoutFaults([at(0)]), [], 'inside the clear zone');
  assert.deepEqual(layoutFaults([at(95)]), ['figure pen clipped by its frame'], 'across the zone\'s edge, on the frame');
  assert.deepEqual(layoutFaults([at(140)]), [], 'wholly clear of the frame');
  assert.ok(!clipped(at(0)) && clipped(at(110)));
});

test('slot helpers: ring tries the authored direction first; beside puts a control margin clear of its anchor', () => {
  const r = ring(boxOf(0, 0, 100, 100), [50, 500], 15);
  assert.equal(r[0][0], 50);
  assert.ok(r[0][1] > 100);
  assert.deepEqual(beside(boxOf(0, 0, 100, 100), 'below', 'end', 40, [20, 10]), [90, -45]);
  assert.deepEqual(beside(boxOf(0, 0, 100, 100), 'right', 'start', 40, [20, 10]), [150, 5]);
});

test('markers: the nearest drawn badge within its circle + 2 px answers (a mouse); partMarkers takes the script\'s numbered parts', () => {
  const proj = { toWorld: (x: number, y: number): [number, number] => [x, y], toScreen: (x: number, y: number): [number, number] => [x, y] };
  const list = partMarkers([{ id: 'a', n: 1, name: 'A', term: 'ta', callout: 'ca' }, { id: 'b', n: 2, name: 'B', term: 'tb' }, { id: 'c', name: 'C', term: 'tc' }],
    (n) => (n === 1 ? [0, 0] : n === 2 ? [30, 0] : null), 10);
  assert.deepEqual(list.map((m) => [m.n, m.term]), [[1, 'ca'], [2, 'tb']]);
  const r = new MarkerRouter(list);
  assert.equal(r.hit(20, 0, proj)?.n, 2);
  assert.equal(r.hit(0, 12, proj)?.n, 1);
  assert.equal(r.hit(0, 13, proj), null);
});

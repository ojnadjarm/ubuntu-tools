import * as THREE from 'three';
import { Ink } from './ink';
import { Tube, Chamber, Pipe } from './parts/glass';
import { Dial, Valve, Gauge } from './parts/meters';
import { Callout, Balloon, Dimension, DetailLink } from './parts/callout';
import { Casing, Sheet, FocusLamp, Veil, caption } from './parts/sheet';
import { NetworkFigure } from './parts/network';
import { ROW, L } from '../units/a01/layout';
import { forward, type Vec2 } from '../sim/neuron';
import { clamp, smooth } from 'explainer-kit';
import type { A01State } from '../units/a01/state';

const LEGEND = ['Glass tube', 'Dial', 'Sum chamber', 'One-way valve', 'Gauge'];

/** Plate I for unit A01, composed from plate parts (Composite); `apply` pushes state and the neuron's arithmetic into all of them. */
export class Plate {
  readonly root = new THREE.Group();
  readonly tubes: [Tube, Tube];
  readonly dials: [Dial, Dial];
  readonly chamber: Chamber;
  readonly valve: Valve;
  readonly gauge: Gauge;
  readonly net: NetworkFigure;
  readonly lamp: FocusLamp;
  readonly veil: Veil;
  private pipes: { inp: Pipe[]; out: Pipe[]; sum: Pipe; res: Pipe };
  private terms: Record<'input' | 'weight1' | 'weight2' | 'output' | 'target', Callout>;
  private dims: { neuron: Dimension; network: Dimension };
  private balloons: Balloon[];
  private detail: DetailLink;

  constructor(ink: Ink) {
    const cl = [L.tubeX - 150, ROW[0], L.dialX + 150, ROW[0], L.tubeX - 150, ROW[1], L.dialX + 150, ROW[1], L.chamberX - 70, 0, L.gaugeX + 150, 0,
      L.dialX, ROW[0] - 150, L.dialX, ROW[0] + 150, L.dialX, ROW[1] - 150, L.dialX, ROW[1] + 150, L.gaugeX, -160, L.gaugeX, 190];
    this.root.add(new Sheet(ink, [-1100, -1300, 1100, 1330], LEGEND).root, new Casing(ink, L.caseW, L.caseH, cl).root);
    this.tubes = ROW.map((y) => new Tube(ink, L.tubeX, y, L.tubeLen, L.tubeR)) as [Tube, Tube];
    this.dials = ROW.map((y) => new Dial(ink, L.dialX, y, L.dialR, L.knobR)) as [Dial, Dial];
    this.chamber = new Chamber(ink, L.chamberX, 0, L.chamberHW, L.chamberH);
    this.valve = new Valve(ink, L.valveX, 0, L.valveR);
    this.gauge = new Gauge(ink, L.gaugeX, 0, L.gaugeR);
    const tx1 = L.tubeX + L.tubeLen / 2 + 16, cx0 = L.chamberX - L.chamberHW - 5;
    this.pipes = {
      inp: ROW.map((y) => new Pipe(ink, [tx1, y, L.dialX - L.dialR, y])),
      out: ROW.map((y) => new Pipe(ink, [L.dialX + L.dialR, y, cx0, y])),
      sum: new Pipe(ink, [L.chamberX + L.chamberHW + 5, 0, L.valveX - L.valveR, 0]),
      res: new Pipe(ink, [L.valveX + L.valveR, 0, L.gaugeX - L.gaugeR - 12, 0]),
    };
    for (const p of [...this.pipes.inp, ...this.pipes.out, this.pipes.sum, this.pipes.res]) this.root.add(p.root);
    for (const p of [...this.tubes, ...this.dials, this.chamber, this.valve, this.gauge]) this.root.add(p.root);

    const tl = L.tubeX - L.tubeLen / 2 - 16;
    this.terms = {
      input: new Callout(ink, [[tl + 30, ROW[0] + 12, -742, 0], [tl + 30, ROW[1] - 12, -742, 0]], [-752, 0], 'INPUT', { align: 'right', role: 'signal', size: 26 }),
      weight1: new Callout(ink, [[L.dialX + 24, ROW[0] + 38, -112, 330, -52, 330]], [-44, 330], 'WEIGHT 1', { role: 'weight', size: 26 }),
      weight2: new Callout(ink, [[L.dialX + 24, ROW[1] - 38, -112, -330, -52, -330]], [-44, -330], 'WEIGHT 2', { role: 'weight', size: 26 }),
      output: new Callout(ink, [[L.gaugeX, -16, L.gaugeX, -330, L.gaugeX + 40, -330]], [L.gaugeX + 48, -330], 'OUTPUT', { role: 'signal', size: 26 }),
      target: new Callout(ink, [[L.gaugeX + 10, L.gaugeR + 42, L.gaugeX + 70, 330, L.gaugeX + 110, 330]], [L.gaugeX + 118, 330], 'TARGET', { role: 'targetInk', size: 26 }),
    };
    this.dims = {
      neuron: new Dimension(ink, -L.caseW / 2, L.caseW / 2, -410, -L.caseH / 2, 'NEURON', 34),
      network: new Dimension(ink, -695, 695, L.netY + 300, L.netY + 250, 'NEURAL NETWORK', 34, false),
    };
    this.balloons = [
      new Balloon(ink, [L.tubeX + 40, ROW[0] + 18, L.tubeX + 90, 232], 1),
      new Balloon(ink, [L.dialX - 88, ROW[0] + 55, L.dialX - 150, 262], 2),
      new Balloon(ink, [L.chamberX + 12, 150, L.chamberX + 60, 238], 3),
      new Balloon(ink, [L.valveX + 10, 30, L.valveX + 34, 150], 4),
      new Balloon(ink, [L.gaugeX - 92, -80, L.gaugeX - 160, -200], 5),
    ];
    for (const c of [...Object.values(this.terms), ...Object.values(this.dims), ...this.balloons]) this.root.add(c.root);
    this.net = new NetworkFigure(ink, L.netY);
    this.detail = new DetailLink(ink, -200, L.netY + 64, 128, [-290, L.netY - 26, -610, 300, -640, 300]);
    this.root.add(this.detail.root);
    this.net.root.add(caption(ink, 'Fig. 2.', -695, L.netY - 275));
    this.root.add(this.net.root, caption(ink, 'Fig. 1.', -L.caseW / 2, -500));
    this.lamp = new FocusLamp(ink);
    this.veil = new Veil(ink);
    this.root.add(this.lamp.root, this.veil.root);
  }

  /** Push state into every part; `run` advances the flowing dashes. */
  apply(s: A01State, dt: number, run: boolean): void {
    const w: Vec2 = [s.w1, s.w2], x: Vec2 = [s.x1, s.x2];
    const o = forward(w, x), f = s.flowOn, open = smooth(clamp(o.sum * 3));
    this.tubes[0].set(s.x1); this.tubes[1].set(s.x2);
    this.dials[0].set(s.w1, s.hiDial1); this.dials[1].set(s.w2, s.hiDial2);
    this.pipes.inp[0].update(x[0] * f, dt, 0.8, run); this.pipes.inp[1].update(x[1] * f, dt, 0.8, run);
    this.pipes.out[0].update(o.contrib[0] * f, dt, 0.8, run); this.pipes.out[1].update(o.contrib[1] * f, dt, 0.8, run);
    this.pipes.sum.update(o.sum * f, dt, 0.7, run);
    this.pipes.res.update(o.out * f * open, dt, 0.7, run);
    this.chamber.set(o.sum, s.chamberOn);
    this.valve.set(open);
    this.gauge.set(o.out * s.chamberOn);
    this.gauge.setTarget(s.target, s.markOn, s.markGlow);
    this.terms.input.set(s.lblInput);
    this.terms.weight1.set(s.lblWeight); this.terms.weight2.set(s.lblWeight);
    this.terms.output.set(s.lblOutput); this.terms.target.set(s.lblTarget);
    this.dims.neuron.set(s.lblNeuron); this.dims.network.set(s.lblNetwork);
    [s.cTubes, s.cDials, s.cChamber, s.cValve, s.cGauge].forEach((v, i) => this.balloons[i].set(v));
    this.net.apply(s.net, s.tuneWall, dt, run);
    this.detail.set(clamp((s.net - 0.12) / 0.43));
  }
}

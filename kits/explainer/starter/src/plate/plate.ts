import * as THREE from 'three';
import { Ink, Sheet, SectionCut, Tube, Column, Dial, Gauge, Pipe, Callout, Balloon, Dimension, FocusLamp, Veil, caption, WEIGHT_SCALE, clamp01 } from 'cutaway-kit';
import type { Explained } from 'explainer-kit';
import { ROW, L, SHEET, LABELS, SPOTS } from '../units/a02/layout';
import { ExplainNote, PartLight } from './explain';
import { output } from '../sim/bias';
import { Tally } from './tally';
import type { A02State } from '../units/a02/state';

const LEGEND = ['Input tube', 'Weight dial', 'Constant source', 'Bias dial', 'Sum column', 'Gauge'];

/** Plate II, the neuron with a bias (Composite of cutaway-kit parts); `apply` pushes state and the sum into every part. */
export class BiasPlate {
  readonly root = new THREE.Group();
  readonly dials: [Dial, Dial];
  readonly lamp: FocusLamp;
  readonly veil: Veil;
  private tubes: [Tube, Tube];
  private col: Column;
  private gauge: Gauge;
  private pipes: { inA: Pipe; inB: Pipe; srcA: Pipe; srcB: Pipe; out: Pipe };
  private terms: Record<'input' | 'weight' | 'bias' | 'output' | 'target', Callout>;
  private name: Dimension;
  private balloons: Balloon[];
  private tally: Tally;
  private note: ExplainNote;
  private lit: PartLight;

  constructor(ink: Ink) {
    const { tubeX, tubeLen, tubeR, dialX, dialR, knobR, colX, colHW, colH, gaugeX, gaugeR } = L;
    const cl = [tubeX - 150, ROW[0], dialX + 150, ROW[0], tubeX - 150, ROW[1], dialX + 150, ROW[1], colX - 70, 0, gaugeX + 150, 0,
      dialX, ROW[0] - 140, dialX, ROW[0] + 140, dialX, ROW[1] - 140, dialX, ROW[1] + 140, gaugeX, -160, gaugeX, 190];
    this.root.add(
      new Sheet(ink, SHEET, { plate: 'Plate II.', title: 'THE BIAS', ref: 'UNIT A02 · SECTION A–A', scale: 'SCALE 1 : 1', sheet: 'SHEET 1 OF 1', legend: LEGEND }).root,
      new SectionCut(ink, L.caseW, L.caseH, cl).root,
    );
    this.tubes = [new Tube(ink, tubeX, ROW[0], tubeLen, tubeR, 3, 'blue'), new Tube(ink, tubeX, ROW[1], tubeLen, tubeR, 1, 'blue')];
    this.dials = ROW.map((y) => new Dial(ink, dialX, y, dialR, knobR, WEIGHT_SCALE, 'red')) as [Dial, Dial];
    this.col = new Column(ink, colX, 0, colHW, colH, -4.5, 4.5, 'blue');
    this.gauge = new Gauge(ink, gaugeX, 0, gaugeR, 4, 'blue', -4);
    const t1 = tubeX + tubeLen / 2 + 16, c0 = colX - colHW - 5;
    this.pipes = {
      inA: new Pipe(ink, [t1, ROW[0], dialX - dialR, ROW[0]]), inB: new Pipe(ink, [dialX + dialR, ROW[0], c0, ROW[0]]),
      srcA: new Pipe(ink, [t1, ROW[1], dialX - dialR, ROW[1]]), srcB: new Pipe(ink, [dialX + dialR, ROW[1], c0, ROW[1]]),
      out: new Pipe(ink, [colX + colHW + 5, 0, gaugeX - gaugeR - 12, 0]),
    };
    for (const p of Object.values(this.pipes)) this.root.add(p.root);
    for (const p of [...this.tubes, ...this.dials, this.col, this.gauge]) this.root.add(p.root);

    const tl = tubeX - tubeLen / 2 - 16, at = (k: keyof typeof LABELS): [number, number] => [LABELS[k].at[0], LABELS[k].at[1]];
    this.terms = {
      input: new Callout(ink, [[tl + 30, ROW[0] + 12, tl - 60, 330, tl - 90, 330]], at('input'), LABELS.input.text, { align: 'right', role: 'blue' }),
      weight: new Callout(ink, [[dialX + 24, ROW[0] + 38, -60, 330, -20, 330]], at('weight'), LABELS.weight.text, { role: 'red' }),
      bias: new Callout(ink, [[dialX + 24, ROW[1] - 38, -60, -330, -20, -330]], at('bias'), LABELS.bias.text, { role: 'red' }),
      output: new Callout(ink, [[gaugeX, -16, gaugeX, -330, gaugeX + 40, -330]], at('output'), LABELS.output.text, { role: 'blue' }),
      target: new Callout(ink, [[gaugeX + 10, gaugeR + 42, gaugeX + 70, 330, gaugeX + 110, 330]], at('target'), LABELS.target.text, { role: 'yellowInk' }),
    };
    this.name = new Dimension(ink, -L.caseW / 2, L.caseW / 2, -430, -L.caseH / 2, LABELS.name.text);
    this.balloons = [
      new Balloon(ink, [tubeX + 40, ROW[0] + 18, tubeX + 90, 222], 1),
      new Balloon(ink, [dialX - 88, ROW[0] + 55, dialX - 140, 225], 2),
      new Balloon(ink, [tubeX + 40, ROW[1] - 18, tubeX + 90, -222], 3),
      new Balloon(ink, [dialX - 88, ROW[1] - 55, dialX - 140, -225], 4),
      new Balloon(ink, [colX + 12, 150, colX + 70, 225], 5),
      new Balloon(ink, [gaugeX - 92, -80, gaugeX - 160, -200], 6),
    ];
    this.tally = new Tally(ink, L.tallyX, L.tallyY);
    for (const c of [...Object.values(this.terms), this.name, ...this.balloons, this.tally]) this.root.add(c.root);
    this.root.add(caption(ink, LABELS.fig1.text, ...at('fig1')));
    this.lamp = new FocusLamp(ink);
    this.veil = new Veil(ink);
    this.note = new ExplainNote(ink);
    this.lit = new PartLight(ink, SPOTS);
    this.root.add(this.lamp.root, this.lit.root, this.note.root, this.veil.root);
  }

  /** Draw the callout of a part (dot, leader, note) or clear it. */
  explain(c: Explained | null): void { this.note.set(c); }
  /** Outline one part (the pointer rests on its number), or none. */
  light(part: string | null): void { this.lit.set(part); }
  /** Where balloon n is drawn now (null: not drawn): the click targets of the callouts. */
  balloonAt(n: number): [number, number] | null { return this.balloons[[1, 2, 3, 4, 5, 6].indexOf(n)]?.at() ?? null; }
  /** After framing: keep the note screen-constant and beside its dot. */
  frame(st: Parameters<ExplainNote['frame']>[0]): void { this.note.frame(st); }
  noteAt(px: number, py: number): 'hear' | 'close' | 'inside' | null { return this.note.hit(px, py); }

  /** Push state into every part; `run` advances the flowing dashes. */
  apply(s: A02State, dt: number, run: boolean): void {
    const f = s.flowOn, out = output(s.w, s.x, s.b, s.src), p = this.pipes;
    this.tubes[0].set(s.x); this.tubes[1].set(s.src);
    this.dials[0].set(s.w, s.hiW); this.dials[1].set(s.b, s.hiB);
    p.inA.update(s.x * f, dt, 0.8, run); p.inB.update(s.w * s.x * f, dt, 0.8, run);
    p.srcA.update(s.src * f, dt, 0.8, run); p.srcB.update(s.b * s.src * f, dt, 0.8, run);
    p.out.update(out * f * s.colOn, dt, 0.7, run);
    this.col.set(out, s.colOn);
    this.gauge.set(out * s.colOn);
    this.gauge.setTarget(s.target, s.markOn, s.markGlow);
    this.terms.input.set(s.lblInput); this.terms.weight.set(s.lblWeight); this.terms.bias.set(s.lblBias);
    this.terms.output.set(s.lblOutput); this.terms.target.set(s.lblTarget);
    this.name.set(s.lblName);
    [s.cIn, s.cW, s.cSrc, s.cB, s.cCol, s.cGauge].forEach((v, i) => this.balloons[i].set(clamp01(v)));
    this.tally.set(s.tallyOn, s.budget, s.clicks);
  }
}

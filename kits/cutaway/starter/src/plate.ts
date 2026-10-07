import * as THREE from 'three';
import { Ink, Sheet, SectionCut, Dial, Gauge, Pipe, Column, Callout, Balloon, Dimension, FocusLamp, Veil, caption, type DialScale } from 'cutaway-kit';
import { L, SHEET, LABELS } from './layout.ts';
import type { PlateState } from './state.ts';

const RATE: DialScale = { min: 0, max: 4, step: 0.5, labels: [0, 1, 2, 3, 4], origin: 0, format: String };

/** Plate 0, the regulator: a sectioned casing, a rate dial, a flow pipe and a gauge with a target (Composite of kit parts). */
export class RegulatorPlate {
  readonly root = new THREE.Group();
  readonly dial: Dial;
  readonly gauge: Gauge;
  readonly lamp: FocusLamp;
  readonly veil: Veil;
  private pipes: Pipe[];
  private meter: Column;
  private terms: { rate: Callout; flow: Callout; target: Callout };
  private name: Dimension;
  private balloons: Balloon[];

  constructor(ink: Ink) {
    const centre = [-L.caseW / 2 + 40, 0, L.caseW / 2 - 40, 0, L.dialX, -170, L.dialX, 170, L.gaugeX, -180, L.gaugeX, 200];
    this.root.add(
      new Sheet(ink, SHEET, { plate: 'Plate 0.', title: 'THE REGULATOR', ref: 'STARTER · SECTION A–A', scale: 'SCALE 1 : 1', sheet: 'SHEET 1 OF 1', legend: ['Rate dial', 'Flow meter', 'Gauge'], drawn: 'Claude', approved: 'Oscar Nadjar' }).root,
      new SectionCut(ink, L.caseW, L.caseH, centre).root,
    );
    this.dial = new Dial(ink, L.dialX, 0, L.dialR, L.knobR, RATE, 'red');
    this.gauge = new Gauge(ink, L.gaugeX, 0, L.gaugeR, 5, 'blue');
    this.meter = new Column(ink, L.meterX, 20, 36, 280, 0, 4, 'blue', { labels: [0, 2, 4], minor: 0.5 });
    this.pipes = [new Pipe(ink, [L.dialX + L.dialR, 0, L.meterX - 32, 0]), new Pipe(ink, [L.meterX + 32, 0, L.gaugeX - L.gaugeR - 12, 0])];
    this.root.add(...this.pipes.map((p) => p.root), this.meter.root, this.dial.root, this.gauge.root);
    const at = (k: keyof typeof LABELS): [number, number] => [LABELS[k].at[0], LABELS[k].at[1]];
    this.terms = {
      rate: new Callout(ink, [[L.dialX + 24, 40, -170, 300, -120, 300]], at('rate'), LABELS.rate.text, { role: 'red' }),
      flow: new Callout(ink, [[L.meterX, -138, L.meterX, -300, 20, -300]], at('flow'), LABELS.flow.text, { role: 'blue' }),
      target: new Callout(ink, [[L.gaugeX + 10, L.gaugeR + 42, L.gaugeX + 70, 300, L.gaugeX + 110, 300]], at('target'), LABELS.target.text, { role: 'yellowInk' }),
    };
    this.name = new Dimension(ink, -L.caseW / 2, L.caseW / 2, -380, -L.caseH / 2, LABELS.name.text);
    this.balloons = [
      new Balloon(ink, [L.dialX - 70, 70, -440, 262], 1),
      new Balloon(ink, [L.meterX + 30, 120, 90, 150], 2),
      new Balloon(ink, [L.gaugeX - 92, -80, 110, -170], 3),
    ];
    for (const p of [...Object.values(this.terms), this.name, ...this.balloons]) this.root.add(p.root);
    this.root.add(caption(ink, LABELS.fig1.text, ...at('fig1')));
    this.lamp = new FocusLamp(ink);
    this.veil = new Veil(ink);
    this.root.add(this.lamp.root, this.veil.root);
  }

  /** Push state into every part; `run` advances the flowing dashes. */
  apply(s: PlateState, dt: number, run: boolean): void {
    this.dial.set(s.rate, s.hiDial);
    this.pipes.forEach((p) => p.update(s.rate * s.flowOn, dt, 0.8, run));
    this.meter.set(s.rate * s.flowOn);
    this.gauge.set(s.rate * s.flowOn);
    this.gauge.setTarget(3, s.markOn, s.markGlow);
    this.terms.rate.set(s.lblRate); this.terms.flow.set(s.lblFlow); this.terms.target.set(s.lblTarget);
    this.name.set(s.lblName);
    [s.cDial, s.cPipe, s.cGauge].forEach((v, i) => this.balloons[i].set(v));
  }
}

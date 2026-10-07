import { Captions as Spoken, type CueSheet, type UnitSpec } from 'explainer-kit';

export type { UnitSpec };

/** Captions on one narration axis: the engine's sentence timing, looked up by narration time. */
export class Captions {
  private spoken: Spoken; private offsets: Record<string, number>;
  constructor(cues: CueSheet, spec: UnitSpec, offsets: Record<string, number>) { this.spoken = new Spoken(cues, spec); this.offsets = offsets; }
  /** The sentence being spoken at narration time t, or ''. */
  at(t: number): string { return this.spoken.watch(t, this.offsets); }
}

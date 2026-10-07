import type { ExerciseSpec, UnitSpec } from '../content/types';

/** How the learner answers: a value set by hand (continuous) or a thing built from parts (construct). Picking from a list is not play. */
export type AnswerSpace = 'continuous' | 'construct';
/** An exercise gesture (Strategy): its name, the answer space it plays in, and what a learner does. */
export interface ExerciseKind { id: string; space: AnswerSpace; gesture: string }

/** The registered exercise kinds; a new gesture registers here instead of adding a branch to the engine. */
export class KindRegistry {
  private map = new Map<string, ExerciseKind>();
  register(k: ExerciseKind): this { this.map.set(k.id, k); return this; }
  get(id: string): ExerciseKind | undefined { return this.map.get(id); }
  ids(): string[] { return [...this.map.keys()]; }
}

/** The kinds every unit starts with. */
export const KINDS = new KindRegistry()
  .register({ id: 'set-commit', space: 'continuous', gesture: 'set a dial, then press it in' })
  .register({ id: 'predict-place', space: 'continuous', gesture: 'place a pencil mark where a value will land' })
  .register({ id: 'make-happen', space: 'continuous', gesture: 'turn until something happens' })
  .register({ id: 'assemble', space: 'construct', gesture: 'seat parts, then run tests' })
  .register({ id: 'repair', space: 'continuous', gesture: 'fix a machine that is off its mark' })
  .register({ id: 'set-tolerance', space: 'continuous', gesture: 'set dials that serve several examples' })
  .register({ id: 'race', space: 'continuous', gesture: 'race a tuner to a smaller miss' })
  .register({ id: 'tune', space: 'continuous', gesture: 'tune the dials by hand to a smaller total miss' });
/** Level kinds: a level may catch nothing, and a misconception it catches needs no contrast pair. */
const LEVELS = ['race', 'tune'];

/** What the unit's code provides for the lint: its clip ids and the misconceptions it has a detector for. */
export interface PlayCode { clips: string[]; detectors: string[] }

/**
 * Play faults (empty = clean): an unregistered kind, an answer space that is not continuous or construct or not the kind's, an exercise that
 * catches nothing (race and tune levels may), a misconception no exercise catches, no detector in code, no refutation or contrast clip, a clip that does not exist.
 */
export function lintPlay(spec: UnitSpec, code: PlayCode, kinds: KindRegistry = KINDS): string[] {
  const out: string[] = [], clips = new Set(code.clips), det = new Set(code.detectors), ex = spec.exercises ?? [], ms = spec.misconceptions ?? [];
  const clip = (what: string, id: string | undefined): void => { if (id && !clips.has(id)) out.push(`${what}: clip ${id} does not exist`); };
  for (const e of ex) {
    const k = kinds.get(e.kind);
    if (!k) out.push(`exercise ${e.id}: kind ${e.kind} is not registered`);
    if (e.answerSpace !== 'continuous' && e.answerSpace !== 'construct') out.push(`exercise ${e.id}: answer space ${e.answerSpace} is a discrete pick`);
    else if (k && k.space !== e.answerSpace) out.push(`exercise ${e.id}: answer space ${e.answerSpace}, but kind ${e.kind} is ${k.space}`);
    if (!e.catches.length && !LEVELS.includes(e.kind)) out.push(`exercise ${e.id}: catches no misconception`);
    for (const m of e.catches) if (!ms.some((x) => x.id === m)) out.push(`exercise ${e.id}: catches unknown misconception ${m}`);
    for (const [k2, id] of Object.entries(e.clips)) clip(`exercise ${e.id} ${k2}`, id);
  }
  const level = (id: string): ExerciseSpec | undefined => ex.find((e) => e.id === id && LEVELS.includes(e.kind));
  for (const m of ms) {
    if (!ex.some((e) => e.catches.includes(m.id))) out.push(`misconception ${m.id}: no exercise catches it`);
    if (!det.has(m.id)) out.push(`misconception ${m.id}: no detector in code`);
    clip(`misconception ${m.id} refutation`, m.refute);
    if (!m.refute) out.push(`misconception ${m.id}: no refutation clip`);
    if (!m.contrast && !level(m.catcher)) out.push(`misconception ${m.id}: no contrast pair`);
    clip(`misconception ${m.id} contrast`, m.contrast);
  }
  return out;
}

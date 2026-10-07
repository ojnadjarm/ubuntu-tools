import type { LearnerStore, UnitProgress } from '../core/store';
import type { Beat, EnterOptions } from './beats';
import type { Director } from './director';
import type { ButtonKind } from './ports';
import { chapterAt, type Chapter } from './chapters';
import { sectionOf, type SectionSpec } from './sections';

export interface TrackOptions {
  /** Unit id in the store (`U01`). */
  unit: string;
  /** Completed beat → progress state (`{ drive: 'driven' }`); entering any beat stores `seen`. */
  states?: Record<string, string>;
  /** The watch beat's name (default `watch`). */
  watch?: string;
}
/** Where a stored unit resumes: the beat and how to enter it, and a line for the Begin card. */
export interface ResumePoint { beat: string; enter: EnterOptions; label: string }

/** What `track` returns: `flush` stores where the learner is right now (the page is hiding), `stop` unsubscribes. */
export interface Tracker { flush(): void; stop(): void }

/** Feed the store from the director's events (Observer): the sentence reached, each beat, each step's snapshot, terms and the furthest second. */
export function track<S extends object>(d: Director<S>, store: LearnerStore, o: TrackOptions): Tracker {
  const watch = o.watch ?? 'watch';
  const save = (p: UnitProgress): void => store.save(o.unit, { furthest: d.furthest, terms: d.named().map((t) => t.id), done: [...d.completed], visited: [...d.visited], ...p });
  const snap = (): UnitProgress => ({ beat: d.beats.name ?? undefined, snap: d.beats.cur?.snapshot?.(), t: undefined });
  const flush = (): void => {
    if (!d.beats.name) return;
    save(d.beats.name === watch ? { beat: watch, t: d.clock.now() } : snap());
  };
  const stop = d.events.on('*', (e) => {
    if (e.type === 'beat') save({ beat: e.name, state: 'seen', snap: undefined, t: e.name === watch ? 0 : undefined });
    else if (e.type === 'span' && d.beats.name === watch) save({ beat: watch, t: e.t });
    else if (e.type === 'seek' && d.beats.name === watch) save({ beat: watch, t: e.to });
    else if (e.type === 'step' || e.type === 'attempt') save(snap());
    else if (e.type === 'complete') save({ ...snap(), state: o.states?.[e.beat] });
  });
  return { flush, stop };
}

/** Put what the store remembers back into a fresh director (reach, named terms, beats entered and done), even when its resume beat is gone; say where it resumes, null when nowhere. */
export function restore<S extends object>(d: Director<S>, store: LearnerStore, o: TrackOptions, sections: SectionSpec[] = []): ResumePoint | null {
  const u = store.unit(o.unit), watch = o.watch ?? 'watch';
  d.reach(Math.min(u.furthest ?? 0, d.tl.duration()));
  for (const id of u.terms ?? []) d.unlock(id);
  for (const b of u.done ?? []) d.completed.add(b);
  for (const b of u.visited ?? []) d.visited.add(b);
  if (!u.beat || !d.beats.get(u.beat)) return null;
  d.visited.add(watch);
  if (u.beat === watch) {
    const t = Math.min(u.t ?? 0, d.furthest);
    return { beat: watch, enter: { at: t }, label: resumeLine({ beat: watch, t }, d.chapters(), sections, d.beats.get(watch)!) };
  }
  d.visited.add(u.beat);
  return { beat: u.beat, enter: u.snap === undefined ? {} : { snap: u.snap }, label: resumeLine({ beat: u.beat, snap: u.snap }, d.chapters(), sections, d.beats.get(u.beat)!) };
}

/** Where a stored unit stopped: the beat, the watch second (watch only) and the beat's snapshot. */
export interface StopPoint { beat: string; t?: number; snap?: unknown }

/** The Begin card's line for an unfinished unit, readable and never an id: the watch chapter, the beat's chapter, the section tab, the beat's own line, then where it stopped. */
export function resumeLine(p: StopPoint, chapters: Chapter[], sections: SectionSpec[], beat: Beat): string {
  if (p.t !== undefined) { const ch = chapterAt(chapters, p.t); return ch ? `You stopped in chapter ${ch.numeral}, ${ch.label}.` : 'You stopped in the watch.'; }
  const ch = chapters.find((c) => c.beat === p.beat);
  if (ch) return `You stopped in chapter ${ch.numeral}, ${ch.label}.`;
  const sec = sectionOf(sections, p.beat);
  if (sec) return `You stopped in ${sec.name}, ${sec.tabs.find((x) => x.beat === p.beat)!.label}.`;
  return beat.resumeLine?.(p.snap) ?? `You stopped at ${beat.where?.(p.snap) ?? beat.label.toLowerCase()}.`;
}

/** The unit is finished: its end was reached, or every chapter is done. */
export function isFinished(chapters: Chapter[], completed: Set<string>): boolean {
  return completed.has('unit') || (chapters.length > 0 && chapters.every((c) => c.done));
}

/** A way on from the landing card: its label and rank, and `continue`, `start` or the beat it opens. */
export interface BeginChoice { label: string; kind: ButtonKind; value: string }
/** The landing card: a line under the lede (or none) and its buttons, the first one primary. */
export interface BeginOffer { line: string | null; choices: BeginChoice[] }
/** What a finished unit offers on landing: its line and one button per way on, each opening a beat. */
export interface FinishedOffer { line: string; choices: { label: string; to: string; kind?: ButtonKind }[] }

/** The landing card (Strategy): Begin on a first visit, Continue / Start over for an unfinished unit, the finished unit's own choices once it is done. */
export function landing(resume: ResumePoint | null, finished: boolean, done?: FinishedOffer): BeginOffer {
  if (finished && done) return { line: done.line, choices: done.choices.map((c, i) => ({ label: c.label, kind: c.kind ?? (i ? 'secondary' : 'primary'), value: c.to })) };
  if (resume) return { line: resume.label, choices: [{ label: 'Continue', kind: 'primary', value: 'continue' }, { label: 'Start over', kind: 'secondary', value: 'start' }] };
  return { line: null, choices: [{ label: 'Begin', kind: 'primary', value: 'continue' }] };
}

import type { EnterOptions } from './beats';
import type { Chapter } from './chapters';

/** A part of the unit outside its chapters (Practice): its name, one tab per beat, and the way back into the lesson. */
export interface SectionSpec { name: string; tabs: { label: string; beat: string }[]; back: { label: string; to: string }; note?: string }
/** What the chrome draws for the open section: the tabs (the open one `current`) and the way back. */
export interface SectionView { name: string; tabs: { label: string; current: boolean; go(): void }[]; back: { label: string; go(): void } }

/** The section that holds `beat`, or null when the beat belongs to the lesson. */
export function sectionOf(specs: SectionSpec[], beat: string | null): SectionSpec | null {
  return beat ? specs.find((s) => s.tabs.some((t) => t.beat === beat)) ?? null : null;
}

/** The chrome's view of the section holding `beat`; `go` opens a beat. */
export function sectionView(specs: SectionSpec[], beat: string | null, go: (beat: string) => void): SectionView | null {
  const s = sectionOf(specs, beat);
  if (!s) return null;
  return { name: s.name, tabs: s.tabs.map((t) => ({ label: t.label, current: t.beat === beat, go: () => go(t.beat) })), back: { label: s.back.label, go: () => go(s.back.to) } };
}

/** Where "Back to the lesson" lands without a beat to return to: the finished unit's `to`, else the first chapter not done (a watch chapter at the furthest second heard). */
export function lessonPoint(chapters: Chapter[], furthest: number, finished: boolean, to: string, watch = 'watch'): { name: string; enter: EnterOptions } {
  const c = finished ? undefined : chapters.find((x) => !x.done);
  if (!c) return { name: to, enter: {} };
  return c.t !== undefined ? { name: watch, enter: { at: furthest } } : { name: c.beat!, enter: {} };
}

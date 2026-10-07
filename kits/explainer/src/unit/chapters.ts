import type { ChapterSpec, UnitSpec } from '../content/types';

/** A chapter row for the bar, the chapter list and the end card; the shell shows only `numeral` until `reached`. */
export interface Chapter { id: string; label: string; numeral: string; t?: number; beat?: string; reached: boolean; done: boolean }
/** What the learner has reached: the furthest watch second, beats entered and beats completed. */
interface Reach { furthest: number; visited: Set<string>; completed: Set<string> }

const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV'];

/** The unit's chapters: `spec.chapters`, else one per watch clip (titled by its `focus`). */
export function chapterSpecs(spec: UnitSpec, offsets: Record<string, number>): ChapterSpec[] {
  if (spec.chapters?.length) return spec.chapters;
  return spec.clips.filter((c) => offsets[c.id] !== undefined).map((c, i) => ({ id: c.id, numeral: ROMAN[i] ?? String(i + 1), title: c.focus ?? c.id, clips: [c.id] }));
}

/** Watch-axis second each chapter's first clip starts at; undefined for a beat chapter or one without clips. */
export function chapterStarts(specs: ChapterSpec[], offsets: Record<string, number>): (number | undefined)[] {
  return specs.map((c) => (c.clips?.length && !c.beat ? Math.min(...c.clips.map((id) => offsets[id] ?? Infinity)) : undefined));
}

/** Chapter rows from the specs and the learner's reach: watch chapters start at their first clip (the first at 0) and are done once heard to the next; a chapter with a beat is that beat's. */
export function chapterList(specs: ChapterSpec[], offsets: Record<string, number>, end: number, r: Reach, starts = chapterStarts(specs, offsets)): Chapter[] {
  const first = starts.findIndex((t) => t !== undefined);
  return specs.map((c, i) => {
    const row = { id: c.id, label: c.title, numeral: c.numeral };
    if (starts[i] === undefined) return { ...row, beat: c.beat, reached: !!c.beat && (r.visited.has(c.beat) || r.completed.has(c.beat)), done: !!c.beat && r.completed.has(c.beat) };
    const t = i === first ? 0 : starts[i]!, next = starts.slice(i + 1).find((x) => x !== undefined) ?? end;
    return { ...row, t, reached: r.furthest >= t - 1e-6, done: r.furthest >= Math.min(next, end) - 0.05 };
  });
}

/** The chapter that holds watch second `t` (the last watch chapter starting at or before it). */
export function chapterAt(list: Chapter[], t: number): Chapter | undefined {
  return list.filter((c) => c.t !== undefined && c.t <= t + 1e-6).at(-1);
}

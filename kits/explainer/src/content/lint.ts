import { textOf, type CueSheet, type UnitSpec } from './types';
import { parseAssert } from './asserts';

const plain = (x: string): string => x.replace(/\{[^}]*\}/g, '').replace(/\|/g, '');
const words = (x: string): number => (x.match(/[A-Za-z0-9'’−-]+/g) ?? []).length;
const has = (text: string, word: string): boolean => new RegExp(`\\b${word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}s?\\b`, 'i').test(text);

/** Content faults in a unit script (and its cue sheet when given): each is one line naming the clip, term or part. Empty = clean. */
export function lintUnit(spec: UnitSpec, cues?: CueSheet): string[] {
  const out: string[] = [];
  const ids = spec.clips.map((c) => c.id), terms = spec.introduces ?? [];
  ids.filter((id, i) => ids.indexOf(id) !== i).forEach((id) => out.push(`clip ${id}: duplicate id`));
  for (const c of spec.clips) c.sentences.forEach((s, i) => {
    if (/\d/.test(plain(textOf(s)))) out.push(`clip ${c.id} sentence ${i + 1}: a digit in narration (say it in words)`);
    if (typeof s !== 'string') for (const a of s.asserts ?? []) { try { parseAssert(a); } catch (e) { out.push(`clip ${c.id} sentence ${i + 1}: ${(e as Error).message}`); } }
  });
  const marks = new Map<string, number>();
  spec.clips.forEach((c, i) => c.sentences.forEach((s) => { for (const m of textOf(s).matchAll(/\{([^}]+)\}/g)) marks.set(`${c.id}.${m[1]}`, i); }));
  const said = (c: UnitSpec['clips'][number], w: string): boolean => c.sentences.some((s) => has(plain(textOf(s)), w));
  /** Index of the clip that names a term (its mark's clip, or the play clip itself). */
  const namedIn = (cue: string): number => {
    if (cue.includes('.')) return marks.get(cue) ?? -1;
    const byMark = [...marks].find(([k]) => k.endsWith(`.${cue}`));
    return byMark ? byMark[1] : ids.indexOf(cue);
  };
  const cueFault = (what: string, cue: string): void => {
    const [clip, mark] = cue.split('.');
    if (!marks.has(cue)) out.push(`${what}: cue ${cue} is no mark`);
    else if (cues && cues.clips[clip]?.marks[mark] === undefined) out.push(`${what}: cue sheet has no ${cue}`);
  };
  for (const t of terms) {
    const n = words(t.gloss), at = namedIn(t.namedCue);
    if (n > 12) out.push(`term ${t.id}: gloss has ${n} words (at most 12)`);
    if (/[.!?]\s+\S/.test(t.gloss.trim())) out.push(`term ${t.id}: gloss is more than one sentence`);
    if (at < 0) { out.push(`term ${t.id}: namedCue ${t.namedCue} is no mark or clip`); continue; }
    if (cues && t.namedCue.includes('.') && cues.clips[t.namedCue.split('.')[0]]?.marks[t.namedCue.split('.')[1]] === undefined) out.push(`term ${t.id}: cue sheet has no ${t.namedCue}`);
    spec.clips.slice(0, at).forEach((c) => { if (said(c, t.word)) out.push(`term ${t.id}: "${t.word}" said in ${c.id}, before it is named`); });
    for (const o of terms) if (o !== t && namedIn(o.namedCue) >= 0 && namedIn(o.namedCue) < at && has(o.gloss, t.word)) out.push(`term ${t.id}: used in the gloss of ${o.id}, named earlier`);
  }
  const known = new Set(terms.map((t) => t.id)), notes = new Set([...known, ...(spec.callouts ?? []).map((c) => c.id)]);
  for (const c of spec.callouts ?? []) {
    if (!known.has(c.term)) out.push(`callout ${c.id}: term ${c.term} is not introduced`);
    if (c.cue) cueFault(`callout ${c.id}`, c.cue);
  }
  for (const p of spec.parts ?? []) {
    if (!known.has(p.term)) out.push(`part ${p.id}: term ${p.term} is not introduced`);
    if (p.callout && !notes.has(p.callout)) out.push(`part ${p.id}: no callout ${p.callout}`);
  }
  for (const ch of spec.chapters ?? []) for (const c of ch.clips ?? []) if (!ids.includes(c)) out.push(`chapter ${ch.numeral}: no clip ${c}`);
  return out;
}

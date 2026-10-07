import { textOf, type CueSheet, type Term, type UnitSpec } from './content/types';

interface Sentence { s: number; e: number; text: string }
/** A sentence on the watch axis: it runs from its start to the next sentence's start, so the spans cover the axis with no holes. */
export interface Span { s: number; e: number; text: string; clip: string }
/** Caption text cut into plain runs and term words. */
export type Token = string | { term: string; text: string };
const plain = (x: string): string => x.replace(/\{[^}]*\}/g, '').replace(/\|$/, '').trim();
const TAIL = /^[,.;:!?)\]\u2019\u201d\u2026]+/;
const esc = (x: string): string => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Index of the span that holds `t` (the last one starting at or before it). */
export function spanAt(spans: Span[], t: number): number {
  let i = 0;
  while (i + 1 < spans.length && spans[i + 1].s <= t + 1e-6) i++;
  return i;
}

/** Captions: the script's sentences, timed by the cue sheet's word timings. */
export class Captions {
  private byClip = new Map<string, Sentence[]>();
  private texts = new Map<string, string>();
  private cues: CueSheet;
  constructor(cues: CueSheet, spec: UnitSpec) {
    this.cues = cues;
    for (const clip of spec.clips) {
      this.texts.set(clip.id, clip.sentences.map((x) => plain(textOf(x))).join(' '));
      const words = cues.clips[clip.id]?.words ?? [], out: Sentence[] = [];
      let i = 0;
      for (const raw of clip.sentences) {
        const text = plain(textOf(raw)), n = (text.match(/[A-Za-z0-9']+/g) ?? []).length;
        const first = words[i], last = words[Math.min(words.length - 1, i + n - 1)];
        if (first && last) out.push({ s: first.s, e: last.e, text });
        i += n;
      }
      this.byClip.set(clip.id, out);
    }
  }
  /** The sentence of clip `id` spoken `t` seconds into it, or ''. */
  at(id: string, t: number): string {
    const list = this.byClip.get(id) ?? [];
    const hit = list.find((x, i) => t >= x.s - 0.15 && t < Math.min(list[i + 1]?.s ?? Infinity, x.e + 0.9) - 0.15);
    return hit ? hit.text : '';
  }
  /** The sentence spoken at watch-axis time `t`. */
  watch(t: number, offsets: Record<string, number>): string {
    for (const [id, at] of Object.entries(offsets)) {
      if (t >= at - 0.2 && t <= at + this.cues.clips[id].duration) return this.at(id, t - at);
    }
    return '';
  }
  /** Sentences of one clip, in seconds from the clip's start. */
  sentences(id: string): Sentence[] { return this.byClip.get(id) ?? []; }
  /** The whole text of a clip, as written (no timings needed). */
  text(id: string): string { return this.texts.get(id) ?? ''; }
  /** The watch clips cut into sentence spans; a clip's first sentence starts at the clip's offset, the watch's first at 0. */
  spans(offsets: Record<string, number>, end: number): Span[] {
    const out: Span[] = [];
    for (const [clip, at] of Object.entries(offsets).sort((a, b) => a[1] - b[1])) {
      this.sentences(clip).forEach((x, i) => out.push({ s: out.length === 0 ? 0 : i === 0 ? at : at + x.s, e: 0, text: x.text, clip }));
    }
    out.forEach((x, i) => { x.e = out[i + 1]?.s ?? end; });
    return out;
  }
  /** Split `text` into plain runs and the words of `terms` (whole words, a plural `s` allowed, first match wins). */
  static tokens(text: string, terms: Pick<Term, 'id' | 'word'>[]): Token[] {
    const list = [...terms].sort((a, b) => b.word.length - a.word.length);
    if (!list.length || !text) return text ? [text] : [];
    const re = new RegExp(`\\b(${list.map((x) => esc(x.word)).join('|')})(s?)\\b`, 'gi');
    const out: Token[] = [];
    let last = 0;
    for (const m of text.matchAll(re)) {
      const term = list.find((x) => x.word.toLowerCase() === m[1].toLowerCase())!;
      if (m.index > last) out.push(text.slice(last, m.index));
      out.push({ term: term.id, text: m[0] });
      last = m.index + m[0].length;
    }
    if (last < text.length) out.push(text.slice(last));
    return out;
  }
  /** The tokens with each term's trailing punctuation moved onto it as `tail`, so a caption line never starts with a comma or a stop. */
  static glued(tokens: Token[]): (string | { term: string; text: string; tail: string })[] {
    return tokens.map((x, i) => {
      if (typeof x !== 'string') { const n = tokens[i + 1]; return { ...x, tail: typeof n === 'string' ? n.match(TAIL)?.[0] ?? '' : '' }; }
      return i > 0 && typeof tokens[i - 1] !== 'string' ? x.replace(TAIL, '') : x;
    }).filter((x) => x !== '');
  }
}

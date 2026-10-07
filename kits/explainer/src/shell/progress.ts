import type { Chapter } from '../unit/chapters';
import { clock, esc } from './icons';

interface ProgressHandlers {
  /** Dragging: follow `t` silently. */
  scrub(t: number): void;
  /** Released or clicked: land on the sentence holding `t`. */
  seek(t: number): void;
  /** A reached chapter's segment after the watch was pressed. */
  chapter(c: Chapter): void;
}
/** Share of the track each chapter played by hand takes, after the watch. */
const SEG = 0.07;
/** A term mark on the bar: where the voice names it. */
interface TermMark { id: string; word: string; at: number }

const pct = (x: number): string => `${(Math.min(1, Math.max(0, x)) * 100).toFixed(2)}%`;

/** The lesson's track: the watch (heard fill, playhead, chapter ticks, term marks; a drag scrubs silently and the release seeks, never past what was heard),
 *  then one segment per chapter played by hand (hollow until reached, inked once done, holding the playhead while open; a press opens a reached one). */
export class ProgressBar {
  readonly el: HTMLElement;
  private track: HTMLElement; private heard: HTMLElement; private head: HTMLElement; private ticks: HTMLElement; private marks: HTMLElement; private segs: HTMLElement; private time: HTMLElement;
  private beat: string | null = null;
  private dur = 1; private furthest = 0; private dragging = false;
  private chs: Chapter[] = []; private tms: TermMark[] = [];
  private last = { heard: '', head: '', time: '', now: -1 };
  private on: ProgressHandlers;
  constructor(on: ProgressHandlers) {
    this.on = on;
    const el = document.createElement('div');
    el.className = 'progress';
    el.innerHTML = `<div class="track" data-k="track" role="slider" tabindex="0" aria-label="Position in the lesson" aria-valuemin="0">`
      + '<span class="rail"></span><span class="heard"></span><span class="segs"></span><span class="ticks"></span><span class="marks"></span><span class="head"></span></div>'
      + '<span class="time" data-k="time"></span>';
    this.el = el;
    const q = (c: string): HTMLElement => el.querySelector(c)!;
    this.track = q('.track'); this.heard = q('.heard'); this.head = q('.head'); this.ticks = q('.ticks'); this.marks = q('.marks'); this.segs = q('.segs'); this.time = q('.time');
    this.track.addEventListener('pointerdown', (e) => {
      const seg = this.segAt(e.clientX);
      if (seg !== undefined) { if (seg?.reached) this.on.chapter(seg); e.preventDefault(); return; }
      this.dragging = true; this.track.setPointerCapture?.(e.pointerId); this.on.scrub(this.at(e.clientX)); e.preventDefault();
    });
    this.track.addEventListener('pointermove', (e) => { if (this.dragging) this.on.scrub(this.at(e.clientX)); });
    const up = (e: PointerEvent): void => { if (!this.dragging) return; this.dragging = false; this.on.seek(this.at(e.clientX)); };
    this.track.addEventListener('pointerup', up);
    this.track.addEventListener('pointercancel', up);
  }
  /** The chapters played by hand (they follow the watch on the track). */
  private get played(): Chapter[] { return this.chs.filter((c) => c.t === undefined && c.beat); }
  /** Share of the track the watch takes. */
  private get W(): number { return 1 - this.played.length * SEG; }
  private frac(x: number): number { const r = this.track.getBoundingClientRect(); return r.width ? (x - r.left) / r.width : 0; }
  /** The played chapter under a client x (null on its gap), undefined over the watch. */
  private segAt(x: number): Chapter | null | undefined {
    const f = this.frac(x), W = this.W;
    if (f <= W) return undefined;
    return this.played[Math.min(this.played.length - 1, Math.floor((f - W) / SEG))] ?? null;
  }
  /** Watch second under a client x, clamped to what was heard. */
  private at(x: number): number { return Math.min(Math.max(0, this.frac(x)) / this.W * this.dur, this.furthest); }
  /** Track share at watch second `t`. */
  private pos(t: number): string { return pct(t / this.dur * this.W); }
  /** The beat now open: its segment holds the playhead. */
  open(beat: string | null): void { this.beat = beat; this.chapters(this.chs); this.last.head = '#'; }
  /** Playhead at `t` (null outside the watch), watch length, furthest second heard. */
  set(at: number | null, dur: number, furthest: number): void {
    const t = at === null ? null : Math.min(at, dur);
    if (Math.abs(dur - this.dur) > 1e-6) { this.dur = Math.max(dur, 1e-6); this.chapters(this.chs); this.terms(this.tms); }
    this.furthest = furthest;
    const seg = t === null ? this.played.findIndex((c) => c.beat === this.beat) : -1;
    const heard = pct(furthest / this.dur * this.W), head = t !== null ? this.pos(t) : seg >= 0 ? pct(this.W + (seg + 0.5) * SEG) : '';
    if (heard !== this.last.heard) { this.last.heard = heard; this.heard.style.width = heard; }
    if (head !== this.last.head) {
      this.last.head = head;
      this.head.hidden = !head;
      if (head) this.head.style.left = head;
    }
    const now = t === null ? -1 : Math.floor(t), time = t === null ? '' : `${clock(t)} / ${clock(dur)}`;
    if (time !== this.last.time) {
      this.last.time = time; this.time.textContent = time;
      this.track.setAttribute('aria-valuemax', String(Math.round(dur)));
      if (now >= 0) { this.track.setAttribute('aria-valuenow', String(now)); this.track.setAttribute('aria-valuetext', time); }
    }
  }
  /** Chapter ticks at each watch chapter's start, then a segment per chapter played by hand; a chapter shows its title once reached. */
  chapters(list: Chapter[]): void {
    this.chs = list;
    const W = this.W, title = (c: Chapter): string => esc(c.reached ? `${c.numeral} · ${c.label}` : c.numeral);
    this.ticks.innerHTML = list.filter((c) => c.t !== undefined && c.t > 0).map((c) =>
      `<i class="tick${c.reached ? ' reached' : ''}" style="left:${this.pos(c.t!)}" title="${title(c)}"></i>`).join('');
    this.segs.innerHTML = this.played.map((c, i) => `<i class="seg${c.reached ? ' reached' : ''}${c.done ? ' done' : ''}${c.beat === this.beat ? ' current' : ''}"`
      + ` data-beat="${esc(c.beat!)}" style="left:${pct(W + i * SEG)};width:${pct(SEG)}" title="${title(c)}"></i>`).join('');
  }
  /** A mark where each named term is said. */
  terms(list: TermMark[]): void {
    this.tms = list;
    this.marks.innerHTML = list.filter((m) => Number.isFinite(m.at)).map((m) =>
      `<i class="tmark" data-term="${esc(m.id)}" style="left:${this.pos(m.at)}" title="${esc(m.word)}"></i>`).join('');
  }
}

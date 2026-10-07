import type { Span } from '../captions';
import type { Chapter } from '../unit/chapters';
import { spanAt } from '../captions';
import { clock, esc } from './icons';

interface SideHandlers {
  /** Go to a reached chapter. */
  chapter(c: Chapter): void;
  /** Seek the watch to a heard sentence (a transcript line). */
  seek(t: number): void;
}
export type SideTab = 'chapters' | 'transcript';

/** The column beside the drawing: the chapters (reached ones open) and the transcript (heard sentences seek). */
export class Side {
  readonly el: HTMLElement;
  private lines: HTMLButtonElement[] = [];
  private spans: Span[] = [];
  private list: Chapter[] = [];
  private tab: SideTab = 'chapters';
  private cur = -1; private heard = -1; private chap = '';
  private on: SideHandlers;
  constructor(on: SideHandlers) {
    this.on = on;
    const el = document.createElement('aside');
    el.className = 'side'; el.setAttribute('aria-label', 'Chapters and transcript');
    el.innerHTML = '<div class="tabs" role="tablist">'
      + '<button role="tab" data-tab="chapters" aria-selected="true">Chapters</button><button role="tab" data-tab="transcript" aria-selected="false">Transcript</button></div>'
      + '<div class="panel" data-panel="chapters" role="tabpanel"><ol class="chapter-list"></ol></div>'
      + '<div class="panel" data-panel="transcript" role="tabpanel" hidden><ol class="transcript"></ol></div>';
    this.el = el;
    el.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => this.show(b.dataset.tab as SideTab)));
    el.querySelector('.chapter-list')!.addEventListener('click', (e) => {
      const b = (e.target as Element).closest<HTMLElement>('[data-i]'), c = b && this.list[Number(b.dataset.i)];
      if (c) this.on.chapter(c);
    });
  }
  /** Which tab is showing. */
  get showing(): SideTab { return this.tab; }
  show(tab: SideTab): void {
    this.tab = tab;
    this.el.querySelectorAll<HTMLElement>('[data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
    this.el.querySelectorAll<HTMLElement>('[data-panel]').forEach((p) => { p.hidden = p.dataset.panel !== tab; });
    if (tab === 'transcript') this.lines[this.cur]?.scrollIntoView({ block: 'nearest' });
  }
  /** The chapter rows: numeral and title, reached ones open, heard ones marked. */
  chapters(list: Chapter[]): void {
    this.list = list;
    const html = list.map((c, i) => `<li class="${c.done ? 'done' : ''}"><button data-i="${i}"${c.reached ? '' : ' disabled'}><span class="num">${esc(c.numeral)}</span>`
      + `<span class="label">${c.reached ? esc(c.label) : 'Not reached yet'}</span></button></li>`).join('');
    if (html === this.chap) return;
    this.chap = html;
    this.el.querySelector('.chapter-list')!.innerHTML = html;
  }
  /** The watch's sentences as transcript lines. */
  transcript(spans: Span[]): void {
    this.spans = spans;
    const ol = this.el.querySelector('.transcript')!;
    ol.innerHTML = spans.map((s) => `<li><button disabled><span class="at">${clock(s.s)}</span> ${esc(s.text)}</button></li>`).join('');
    this.lines = [...ol.querySelectorAll('button')];
    this.lines.forEach((b, i) => b.addEventListener('click', () => this.on.seek(this.spans[i].s)));
    this.heard = -1; this.cur = -1;
  }
  /** Enable the heard lines and mark the one playing (t null outside the watch). */
  follow(t: number | null, furthest: number): void {
    if (!this.spans.length) return;
    const h = spanAt(this.spans, furthest);
    for (let i = this.heard + 1; i <= h; i++) this.lines[i].disabled = false;
    this.heard = Math.max(this.heard, h);
    const c = t === null ? -1 : spanAt(this.spans, t);
    if (c === this.cur) return;
    this.lines[this.cur]?.removeAttribute('aria-current');
    this.cur = c;
    if (c < 0) return;
    this.lines[c].setAttribute('aria-current', 'true');
    if (this.tab === 'transcript' && !this.el.hidden) this.lines[c].scrollIntoView({ block: 'nearest' });
  }
}

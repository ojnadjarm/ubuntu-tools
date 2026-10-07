import type { Bus } from '../audio/voice';
import type { Span } from '../captions';
import { Captions } from '../captions';
import type { Chapter } from '../unit/chapters';
import type { EndCard, Explained, NamedTerm, ShellPort, Working } from '../unit/ports';
import { landing, type BeginOffer } from '../unit/resume';
import { ICON, esc } from './icons';
import { ProgressBar } from './progress';
import { Side, type SideTab } from './side';
import { Pops, type PopKind, type SectionEntry } from './pops';
import { SectionHead } from './section';
import type { SectionView } from '../unit/sections';
import { keyHint } from '../play/keys';

/** Everything the chrome says; the style's CSS decides how it looks. */
export interface ShellText {
  num: string; name: string; eyebrow: string; title: string; lede: string; endEyebrow: string; endTitle: string; again?: string;
  /** The key line on the Begin card (default: `keyHint()`, quoted from the key table). */
  keys?: string;
  /** One line under the keys on the Begin card (default: click a circled number to open its note, Esc closes it). */
  tip?: string;
  /** A line under the end title. */
  endLede?: string;
}
/** What the chrome asks the player to do. */
export interface ShellActions {
  toggle(): void; replay(): void; back(): void;
  scrub(t: number): void; seek(t: number): void;
  open(term: string): void; hear(): void; close(): void;
  chapter(c: Chapter): void; say(): void; hint(): void; giveUp(): void;
  volume(bus: Bus, v: number): void; mute(): void; cc(on: boolean): void;
}
const NOOP: ShellActions = {
  toggle() {}, replay() {}, back() {}, scrub() {}, seek() {}, open() {}, hear() {}, close() {},
  chapter() {}, say() {}, hint() {}, giveUp() {}, volume() {}, mute() {}, cc() {},
};

/** Page chrome as DOM only (Humble Object: it renders what the director says and forwards clicks to `on`); no CSS here. */
export class Shell implements ShellPort {
  on: ShellActions = { ...NOOP };
  readonly bar: ProgressBar;
  readonly side: Side;
  readonly pops: Pops;
  readonly head = new SectionHead();
  private chooser: EndCard | null = null;
  private endText: { eyebrow: string; title: string; lede: string };
  private el: Record<string, HTMLElement> = {};
  private go: (() => void) | null = null;
  private offered: (() => void) | null = null;
  private cc = false;
  private pressed = false;
  private beginLabel = 'Begin';
  private words: NamedTerm[] = [];
  private text = '';
  private said = '';
  private list: Chapter[] = [];

  constructor(root: HTMLElement, t: ShellText) {
    root.innerHTML = `
      <header class="mark"><span class="num">${t.num}</span><span>${t.name}</span></header>
      <section class="card begin" role="dialog" aria-labelledby="t-begin">
        <p class="eyebrow">${t.eyebrow}</p>
        <h1 id="t-begin">${t.title}</h1>
        <p class="lede">${t.lede}</p>
        <p class="resume" data-k="resume" hidden></p>
        <div class="choices" data-k="beginchoices"><button class="btn primary" data-k="begin">Begin</button></div>
        <p class="keys">${t.keys ?? keyHint()}</p>
        <p class="tip">${t.tip ?? 'Click or tap a circled number to open its note; Esc, a click on bare paper or the same number closes it.'}</p>
      </section>
      <div class="instruction" data-k="instruction" hidden><p data-k="ask" hidden></p><div class="acts">
        <button class="btn quiet act" data-k="say" data-key="J" hidden>Say again</button><button class="btn secondary act" data-k="hint" data-key="H" hidden>Hint</button><button class="btn quiet act" data-k="giveup" hidden>Give up</button><button class="btn secondary act go" data-k="offer" hidden></button></div></div>
      <p class="caption" data-k="caption" aria-live="polite" hidden></p>
      <button class="btn primary cta" data-k="cta" hidden></button>
      <section class="card end" data-k="end" role="dialog" aria-labelledby="t-end" hidden>
        <button class="btn icon end-close" data-k="end-close" aria-label="Close">${ICON.cross}</button>
        <p class="eyebrow" data-k="end-eyebrow">${t.endEyebrow}</p>
        <h2 id="t-end" data-k="end-title">${t.endTitle}</h2>
        <p class="lede" data-k="end-lede"${t.endLede ? '' : ' hidden'}>${t.endLede ?? ''}</p>
        <ol class="chapter-list" data-k="endlist"></ol>
        <div class="choices" data-k="endchoices" hidden></div>
        <div class="next-sheet" data-k="endnext" hidden></div>
        <button class="btn primary" data-k="again">${t.again ?? 'Replay from the start'}</button>
      </section>
      <section class="note-a11y" data-k="note" aria-live="polite" hidden>
        <h2 data-k="note-title"></h2><p data-k="note-gloss"></p><p data-k="note-now"></p>
        <button class="btn secondary" data-k="hear">Hear it</button><button class="btn quiet" data-k="note-close">Close</button>
      </section>
      <nav class="bar" aria-label="Playback">
        <button class="btn icon" data-k="toggle" aria-label="Pause">${ICON.pause}</button>
        <button class="btn icon" data-k="back" aria-label="Back one sentence">${ICON.back}</button>
        <span data-k="progress"></span>
        <span class="grow" data-k="status"></span>
        <button class="btn icon" data-k="chapters" data-pop aria-label="Chapters">${ICON.list}</button>
        <button class="btn icon" data-k="working" data-pop aria-label="Working" hidden>${ICON.sheet}</button>
        <button class="btn toggle" data-k="cc" aria-pressed="false">CC</button>
        <button class="btn icon" data-k="sound" data-pop aria-label="Sound">${ICON.sound}</button>
        <span class="sections" data-k="sections"></span>
        <button class="btn toggle" data-k="help" data-pop aria-label="Keys">?</button>
      </nav>`;
    root.querySelectorAll<HTMLElement>('[data-k]').forEach((n) => { this.el[n.dataset.k!] = n; });
    this.bar = new ProgressBar({ scrub: (x) => this.on.scrub(x), seek: (x) => this.on.seek(x), chapter: (c) => this.on.chapter(c) });
    this.el.progress.replaceWith(this.bar.el);
    this.side = new Side({ chapter: (c) => this.on.chapter(c), seek: (x) => this.on.seek(x) });
    this.pops = new Pops({ chapter: (c) => this.on.chapter(c), volume: (b, v) => this.on.volume(b, v), mute: () => this.on.mute() });
    this.endText = { eyebrow: t.endEyebrow, title: t.endTitle, lede: t.endLede ?? '' };
    root.append(this.head.el, this.side.el, this.pops.el);
    const click = (k: string, f: () => void): void => this.el[k].addEventListener('click', f);
    click('cta', () => { const g = this.go; this.cta(null); g?.(); });
    click('toggle', () => this.on.toggle());
    click('back', () => this.on.back());
    click('again', () => { this.el.end.hidden = true; this.on.replay(); });
    this.el.endchoices.addEventListener('click', (e) => {
      const b = (e.target as Element).closest<HTMLElement>('[data-c]'), c = b && this.chooser?.choices[Number(b.dataset.c)];
      if (!c) return;
      this.el.end.hidden = true; this.chooser = null; this.cta(null);
      c.go();
    });
    click('end-close', () => this.closeEnd());
    addEventListener('pointerdown', (e) => {
      const t = e.target as Node;
      if (this.el.end.hidden || this.el.end.contains(t)) return;
      this.closeEnd();
      if (!root.contains(t)) e.stopPropagation();
    }, true);
    click('cc', () => { this.captions(!this.cc); this.on.cc(this.cc); });
    click('chapters', () => { if (matchMedia('(min-width: 1024px)').matches) this.sideTab('chapters'); else this.pops.toggle('chapters'); });
    click('working', () => this.pops.toggle('working'));
    click('sound', () => this.pops.toggle('sound'));
    click('help', () => this.pops.toggle('keys'));
    this.el.sections.addEventListener('click', (e) => { const b = (e.target as Element).closest<HTMLElement>('[data-s]'); if (b) this.pops.section(Number(b.dataset.s)); });
    click('say', () => this.on.say());
    click('hint', () => this.on.hint());
    click('giveup', () => this.on.giveUp());
    click('offer', () => { const g = this.offered; this.offer(null); g?.(); });
    this.el.endlist.addEventListener('click', (e) => { const b = (e.target as Element).closest<HTMLElement>('[data-i]'); const c = b && this.list[Number(b.dataset.i)]; if (c) { this.el.end.hidden = true; this.on.chapter(c); } });
    click('hear', () => this.on.hear());
    click('note-close', () => this.on.close());
    this.el.caption.addEventListener('click', (e) => { const b = (e.target as Element).closest<HTMLElement>('[data-term]'); if (b) this.on.open(b.dataset.term!); });
  }

  /** Resolves with the value of the landing card's button the learner presses (a user gesture, so audio may start); the first button is the primary. */
  begin(offer: BeginOffer = landing(null, false)): Promise<string> {
    const box = this.el.beginchoices;
    this.beginLabel = offer.choices[0].label;
    this.el.resume.textContent = offer.line ?? ''; this.el.resume.hidden = !offer.line;
    box.innerHTML = offer.choices.map((c, i) => `<button class="btn ${c.kind}" ${i ? `data-c="${i}"` : 'data-k="begin"'}>${esc(c.label)}</button>`).join('');
    this.el.begin = box.querySelector<HTMLElement>('[data-k=begin]')!;
    return new Promise((res) => {
      const pick = (e: Event): void => {
        const b = (e.target as Element).closest<HTMLElement>('button');
        if (!b || this.pressed) return;
        this.pressed = true;
        if (b === this.el.begin && b.classList.contains('loading')) b.textContent = 'Starting…';
        res(offer.choices[b === this.el.begin ? 0 : Number(b.dataset.c)].value);
      };
      box.addEventListener('click', pick);
    });
  }
  /** Warm-up progress on the Begin button (0 → 1); a press before 1 is kept. */
  warm(f: number): void {
    const b = this.el.begin;
    b.classList.toggle('loading', f < 1);
    b.style.setProperty('--p', `${Math.round(f * 100)}%`);
    b.textContent = f >= 1 ? this.beginLabel : this.pressed ? 'Starting…' : 'Preparing…';
  }
  /** Hide the Begin card and show the playing chrome (frozen stills call it too). */
  live(): void { document.body.classList.add('live'); }
  /** Captions are showing. */
  get captioned(): boolean { return this.cc; }
  captions(on: boolean): void { this.cc = on; this.el.cc.setAttribute('aria-pressed', String(on)); this.el.caption.hidden = !on; }
  muted(on: boolean, vol: Record<Bus, number>): void {
    this.el.sound.innerHTML = on ? ICON.muted : ICON.sound;
    this.el.sound.setAttribute('aria-label', on ? 'Sound (muted)' : 'Sound');
    this.pops.volumes(vol, on);
  }
  /** Show a side tab, or close the column when that tab is already showing. */
  sideTab(tab: SideTab): void {
    const open = !document.body.classList.contains('side-closed');
    const close = open && this.side.showing === tab;
    document.body.classList.toggle('side-closed', close);
    if (!close) this.side.show(tab);
  }
  pop(kind: PopKind): void { this.pops.toggle(kind); }
  /** One quiet toggle per section in the bar, opening a sheet of its tabs (hidden while that section is open). */
  sections(list: SectionEntry[]): void {
    this.pops.sections(list);
    this.el.sections.innerHTML = list.map((x, i) => `<button class="btn toggle" data-k="section" data-s="${i}" data-pop aria-haspopup="dialog">${esc(x.name)}</button>`).join('');
  }

  cta(label: string | null, go?: () => void): void {
    this.go = go ?? null;
    const b = this.el.cta;
    if (!label) { b.hidden = true; return; }
    b.textContent = label; b.hidden = false;
    if (document.activeElement === document.body || !document.activeElement) b.focus({ preventScroll: true });
  }
  /** The sentence being said; blank while it is the standing instruction's own words (the box already shows them). */
  caption(said: string): void {
    this.said = said;
    const ask = this.el.ask.hidden ? '' : this.el.ask.textContent ?? '', text = said && ask.includes(said.trim()) ? '' : said;
    if (text === this.text) return;
    this.text = text;
    this.el.caption.innerHTML = Captions.glued(Captions.tokens(text, this.words)).map((x) => typeof x === 'string' ? esc(x)
      : `<span class="glue"><button class="term" data-term="${esc(x.term)}">${esc(x.text)}</button>${esc(x.tail)}</span>`).join('');
  }
  playing(on: boolean): void {
    this.el.toggle.innerHTML = on ? ICON.pause : ICON.play;
    this.el.toggle.setAttribute('aria-label', on ? 'Pause' : 'Play');
  }
  pausable(on: boolean): void { (this.el.toggle as HTMLButtonElement).disabled = !on; }
  end(onReplay: () => void, card?: EndCard): void {
    this.on.replay = onReplay;
    this.chooser = card ?? null;
    const w = { ...this.endText, ...card };
    this.el['end-eyebrow'].textContent = w.eyebrow; this.el['end-title'].textContent = w.title;
    this.el['end-lede'].textContent = w.lede; this.el['end-lede'].hidden = !w.lede;
    this.el.endchoices.innerHTML = (card?.choices ?? []).map((c, i) => `<button class="btn ${c.kind ?? (i ? 'secondary' : 'primary')}" data-c="${i}">${esc(c.label)}</button>`).join('');
    this.el.endchoices.hidden = !card;
    this.el.endlist.hidden = this.el.again.hidden = !!card;
    const nx = card?.next;
    this.el.endnext.innerHTML = !nx ? '' : nx.href ? `<a class="btn quiet" href="${esc(nx.href)}">${esc(nx.label)}</a>` : `<p class="next phantom" aria-disabled="true">${esc(nx.label)}</p>`;
    this.el.endnext.hidden = !nx;
    this.openEnd();
  }
  private openEnd(): void {
    this.cta(null);
    this.el.end.hidden = false;
    this.endList();
    (this.el.endchoices.hidden ? this.el['end-close'] : this.el.endchoices.querySelector<HTMLElement>('button'))?.focus({ preventScroll: true });
  }
  /** Close the end card (the ×, Esc, a press outside it); the plate behind stays live, and a chooser leaves a button that opens it again. `leaving` drops both. False when it was not open. */
  closeEnd(leaving = false): boolean {
    if (leaving) this.chooser = null;
    if (this.el.end.hidden) return false;
    this.el.end.hidden = true;
    if (this.chooser) this.cta('What next?', () => this.openEnd());
    return true;
  }
  status(text: string): void { if (this.el.status.textContent !== text) this.el.status.textContent = text; }

  progress(t: number | null, dur: number, furthest: number): void { this.bar.set(t, dur, furthest); this.side.follow(t, furthest); }
  chapters(list: Chapter[]): void { this.list = list; this.bar.chapters(list); this.pops.chapters(list); this.side.chapters(list); if (!this.el.end.hidden) this.endList(); }
  private endList(): void {
    this.el.endlist.style.setProperty('--rows', String(Math.ceil(this.list.length / 2)));
    this.el.endlist.innerHTML = this.list.map((c, i) => `<li class="${c.done ? 'done' : ''}"><button data-i="${i}"${c.reached ? '' : ' disabled'}><span class="num">${esc(c.numeral)}</span>`
      + `<span class="label">${esc(c.label)}</span></button></li>`).join('');
  }
  terms(list: NamedTerm[]): void {
    this.words = list;
    this.bar.terms(list.map((x) => ({ id: x.id, word: x.word, at: x.at })));
    this.text = ''; this.caption(this.said);
  }
  explain(c: Explained | null): void {
    const n = this.el.note;
    n.hidden = !c;
    if (!c) return;
    this.el['note-title'].textContent = c.available ? c.title : c.chapter ? `Chapter ${c.chapter.numeral}` : '';
    this.el['note-gloss'].textContent = c.available ? c.what : c.chapter ? `Explained in chapter ${c.chapter.numeral}.` : 'Explained later in the lesson.';
    this.el['note-now'].textContent = c.now ?? '';
    this.el.hear.hidden = !c.available || !c.said;
  }
  instruction(text: string | null): void {
    this.el.ask.textContent = text ?? '';
    this.el.ask.hidden = this.el.say.hidden = !text;
    this.el.instruction.hidden = !text && this.el.offer.hidden;
    this.caption(this.said);
  }
  hintable(on: boolean, label?: string): void { this.el.hint.hidden = !on; if (label) this.el.hint.textContent = label; }
  offer(label: string | null, go?: () => void): void {
    this.offered = go ?? null;
    this.el.offer.hidden = !label;
    if (label) this.el.offer.textContent = label;
    this.el.instruction.hidden = !label && this.el.ask.hidden;
  }
  spans(list: Span[]): void { this.side.transcript(list); }
  working(blocks: Working[]): void {
    this.pops.working(blocks);
    this.el.working.hidden = !this.pops.worked;
    if (!this.pops.worked && this.pops.kind === 'working') this.pops.close();
  }
  giveable(on: boolean): void { this.el.giveup.hidden = !on; }
  section(v: SectionView | null): void { this.head.set(v); }
  /** The beat now open (the bar's segment for a chapter played by hand). */
  beat(name: string | null): void { this.bar.open(name); }
}

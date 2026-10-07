import type { Bus } from '../audio/voice';
import type { Chapter } from '../unit/chapters';
import type { Working } from '../unit/ports';
import { KEYS } from '../play/keys';
import { ICON, esc } from './icons';

interface PopHandlers {
  /** Go to a reached chapter. */
  chapter(c: Chapter): void;
  volume(bus: Bus, v: number): void;
  mute(): void;
}
export type PopKind = 'keys' | 'chapters' | 'sound' | 'working' | 'section';
const TITLE: Record<Exclude<PopKind, 'section'>, string> = { keys: 'Keys', chapters: 'Chapters', sound: 'Sound', working: 'Working' };
/** A section's entry in the bar: its name, a line under its tabs, and each tab's way in. */
export interface SectionEntry { name: string; note?: string; tabs: { label: string; go(): void }[] }

/** One small sheet above the bar at a time: the keys (`?`), the chapter list, the voice and effects volumes, the working drawn on the plate, a section's tabs. */
export class Pops {
  readonly el: HTMLElement;
  kind: PopKind | null = null;
  private list: Chapter[] = [];
  private vol: Record<Bus, number> = { voice: 1, sfx: 1 };
  private muted = false;
  private work: Working[] = [];
  private secs: SectionEntry[] = [];
  private sec = 0;
  private workKey = '';
  private on: PopHandlers;
  constructor(on: PopHandlers) {
    this.on = on;
    const el = document.createElement('section');
    el.className = 'pop'; el.hidden = true; el.setAttribute('role', 'dialog');
    this.el = el;
    addEventListener('pointerdown', (e) => {
      const t = e.target as Element | null;
      if (this.kind && !el.contains(t) && !t?.closest?.('[data-pop]')) this.close();
    });
  }
  /** Open `kind` (again: close it). */
  toggle(kind: PopKind): void { if (this.kind === kind) this.close(); else this.open(kind); }
  open(kind: PopKind): void {
    this.kind = kind;
    this.el.hidden = false;
    this.el.setAttribute('aria-label', this.title(kind));
    this.render();
    this.el.querySelector<HTMLElement>('button:not([disabled]), input')?.focus({ preventScroll: true });
  }
  /** Close whatever is open; false if nothing was. */
  close(): boolean { if (!this.kind) return false; this.kind = null; this.el.hidden = true; this.el.innerHTML = ''; return true; }
  sections(list: SectionEntry[]): void { this.secs = list; }
  /** Open section `i`'s sheet (again: close it). */
  section(i: number): void { if (this.kind === 'section' && this.sec === i) this.close(); else { this.sec = i; this.open('section'); } }
  private title(k: PopKind): string { return k === 'section' ? this.secs[this.sec]?.name ?? '' : TITLE[k]; }
  chapters(list: Chapter[]): void { this.list = list; if (this.kind === 'chapters') this.render(); }
  /** The working the plate draws now, as text; the open sheet follows it. */
  working(blocks: Working[]): void {
    const w = blocks.filter((b) => b.rows.length), key = JSON.stringify(w);
    if (key === this.workKey) return;
    this.work = w; this.workKey = key;
    if (this.kind === 'working') this.render();
  }
  /** Something is worked on the plate now. */
  get worked(): boolean { return this.work.length > 0; }
  volumes(v: Record<Bus, number>, muted: boolean): void { this.vol = { ...v }; this.muted = muted; if (this.kind === 'sound') this.render(); }
  private render(): void {
    const k = this.kind; if (!k) return;
    const head = `<h2>${esc(this.title(k))}</h2><button class="btn icon close" data-k="pop-close" aria-label="Close">${ICON.cross}</button>`;
    if (k === 'keys') {
      this.el.innerHTML = `${head}<dl class="keys-sheet">${KEYS.map((r) => `<dt>${r.keys.map((x) => `<kbd>${esc(x)}</kbd>`).join(' ')}</dt><dd>${esc(r.does)}</dd>`).join('')}</dl>`;
    } else if (k === 'chapters') {
      this.el.innerHTML = `${head}<ol class="chapter-list">${this.list.map((c, i) =>
        `<li class="${c.done ? 'done' : ''}"><button data-i="${i}"${c.reached ? '' : ' disabled'}><span class="num">${esc(c.numeral)}</span>`
        + `<span class="label">${c.reached ? esc(c.label) : 'Not reached yet'}</span></button></li>`).join('')}</ol>`;
      this.el.querySelectorAll<HTMLButtonElement>('[data-i]').forEach((b) => b.addEventListener('click', () => { this.close(); this.on.chapter(this.list[Number(b.dataset.i)]); }));
    } else if (k === 'section') {
      const x = this.secs[this.sec];
      this.el.innerHTML = `${head}<div class="section-ways">${x.tabs.map((t, i) => `<button class="btn secondary" data-t="${i}">${esc(t.label)}</button>`).join('')}</div>`
        + (x.note ? `<p class="empty">${esc(x.note)}</p>` : '');
      this.el.querySelectorAll<HTMLButtonElement>('[data-t]').forEach((b) => b.addEventListener('click', () => { this.close(); x.tabs[Number(b.dataset.t)].go(); }));
    } else if (k === 'working') {
      this.el.innerHTML = `${head}<div class="working">${this.work.map((b) => `<h3>${esc(b.title)}</h3><ol>${b.rows.map((r) => `<li>${esc(r)}</li>`).join('')}</ol>`).join('')
        || '<p class="empty">Nothing is worked on the plate now.</p>'}</div>`;
    } else {
      const row = (bus: Bus, label: string): string => `<label><span>${label}</span><input type="range" min="0" max="1" step="0.05" value="${this.vol[bus]}" data-bus="${bus}"></label>`;
      this.el.innerHTML = `${head}<div class="sound">${row('voice', 'Voice')}${row('sfx', 'Effects')}`
        + `<button class="btn toggle" data-k="mute" aria-pressed="${this.muted}">${this.muted ? 'Sound off' : 'Sound on'}</button></div>`;
      this.el.querySelector('[data-k=mute]')!.addEventListener('click', () => this.on.mute());
      this.el.querySelectorAll<HTMLInputElement>('[data-bus]').forEach((i) => i.addEventListener('input', () => {
        const bus = i.dataset.bus as Bus; this.vol[bus] = Number(i.value); this.on.volume(bus, this.vol[bus]);
      }));
    }
    this.el.querySelector('[data-k=pop-close]')!.addEventListener('click', () => this.close());
  }
}

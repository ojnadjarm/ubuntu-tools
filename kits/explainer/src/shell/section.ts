import type { SectionView } from '../unit/sections';
import { ICON, esc } from './icons';

/** The header of a section outside the chapters (Humble Object): its name, a tab per beat and the way back to the lesson; marked
 * `data-stage-top`, so a stage that reads its chrome frames the drawing below it. */
export class SectionHead {
  readonly el: HTMLElement;
  private view: SectionView | null = null;
  private key = '';
  constructor() {
    const el = document.createElement('header');
    el.className = 'section-head'; el.hidden = true; el.dataset.stageTop = '';
    el.addEventListener('click', (e) => {
      const b = (e.target as Element).closest<HTMLElement>('[data-s]'), v = this.view;
      if (!b || !v) return;
      const k = b.dataset.s!;
      if (k === 'back') v.back.go(); else if (!v.tabs[Number(k)].current) v.tabs[Number(k)].go();
    });
    this.el = el;
  }
  /** Show the open section, or hide the head (null: the learner is in the lesson). */
  set(v: SectionView | null): void {
    this.view = v;
    document.body.classList.toggle('in-section', !!v);
    this.el.hidden = !v;
    const key = v ? `${v.name}|${v.tabs.map((t) => `${t.label}${t.current ? '*' : ''}`).join()}|${v.back.label}` : '';
    if (!v || key === this.key) return;
    this.key = key;
    this.el.setAttribute('aria-label', v.name);
    this.el.innerHTML = `<button class="btn back" data-s="back">${ICON.left}<span>${esc(v.back.label)}</span></button>`
      + `<h2 class="section-name">${esc(v.name)}</h2>`
      + `<nav class="section-tabs" aria-label="${esc(v.name)}">${v.tabs.map((t, i) => `<button class="btn tab" data-s="${i}"${t.current ? ' aria-current="page"' : ''}>${esc(t.label)}</button>`).join('')}</nav>`;
  }
}

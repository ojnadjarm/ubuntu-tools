const ICON = {
  play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13l10.5-6.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"/></svg>',
  replay: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a7 7 0 1 1-6.6 4.7l1.9.6A5 5 0 1 0 12 7v3L7.5 6 12 2z"/></svg>',
};

/** What the Begin card and the corner mark say. */
export interface ShellText { num: string; name: string; eyebrow: string; title: string; lede: string; keys: string }

/** Page chrome (from the T71 neuron plate): Begin card, control bar with pause, replay, status and CC, optional captions. */
export class Shell {
  private el: Record<string, HTMLElement> = {};
  private cc = false;
  onToggle: () => void = () => undefined;
  onReplay: () => void = () => undefined;

  constructor(root: HTMLElement, t: ShellText) {
    root.innerHTML = `
      <header class="mark"><span class="num">${t.num}</span><span>${t.name}</span></header>
      <section class="card begin" role="dialog" aria-labelledby="t-begin">
        <p class="eyebrow">${t.eyebrow}</p>
        <h1 id="t-begin">${t.title}</h1>
        <p class="lede">${t.lede}</p>
        <button class="btn primary" type="button" data-k="begin">Begin</button>
        <p class="keys">${t.keys}</p>
      </section>
      <p class="caption" data-k="caption" aria-live="polite" hidden></p>
      <nav class="bar" aria-label="Playback">
        <button class="btn icon" type="button" data-k="toggle" aria-label="Pause">${ICON.pause}</button>
        <button class="btn icon" type="button" data-k="replay" aria-label="Replay from the start">${ICON.replay}</button>
        <span class="grow" data-k="status">Watch</span>
        <button class="btn toggle" type="button" data-k="cc" aria-pressed="false">CC</button>
      </nav>`;
    root.querySelectorAll<HTMLElement>('[data-k]').forEach((n) => { this.el[n.dataset.k!] = n; });
    this.el.toggle.addEventListener('click', () => this.onToggle());
    this.el.replay.addEventListener('click', () => this.onReplay());
    this.el.cc.addEventListener('click', () => this.captions(!this.cc));
  }
  /** Resolves when the learner presses Begin (a user gesture, so audio may start); then the bar shows. */
  begin(): Promise<void> {
    return new Promise((res) => this.el.begin.addEventListener('click', () => { this.live(); res(); }, { once: true }));
  }
  /** Show the playing chrome: frozen stills call this too, so the bar is in every still. */
  live(): void { document.body.classList.add('live'); }
  captions(on: boolean): void { this.cc = on; this.el.cc.setAttribute('aria-pressed', String(on)); this.el.caption.hidden = !on; }
  caption(text: string): void { if (this.el.caption.textContent !== text) this.el.caption.textContent = text; }
  playing(on: boolean): void { this.el.toggle.innerHTML = on ? ICON.pause : ICON.play; this.el.toggle.setAttribute('aria-label', on ? 'Pause' : 'Play'); }
  pausable(on: boolean): void { (this.el.toggle as HTMLButtonElement).disabled = !on; }
  status(text: string): void { if (this.el.status.textContent !== text) this.el.status.textContent = text; }
}

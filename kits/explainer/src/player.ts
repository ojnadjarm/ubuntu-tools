import type { Bus, Voice } from './audio/voice';
import type { LearnerStore } from './core/store';
import { PointerRouter } from './play/pointer';
import { MarkerRouter } from './play/markers';
import { bindKeys, type KeyActions } from './play/keys';
import { ZoomControl } from './shell/zoom';
import type { Director } from './unit/director';
import type { Chapter } from './unit/chapters';
import type { View } from './unit/ports';
import type { Shell } from './shell/shell';
import type { EnterOptions } from './unit/beats';
import { lessonPoint, sectionOf, sectionView, type SectionSpec } from './unit/sections';
import { isFinished } from './unit/resume';

interface PlayerParts<S extends object> { d: Director<S>; shell: Shell; view: View<S>; voice: Voice; store: LearnerStore; watch?: string; markers?: MarkerRouter; sections?: SectionSpec[] }

/** Player actions over the director (Facade): seek, chapters, callouts, sound and captions, shared by the chrome and the keys. */
export class Player<S extends object> {
  private d: Director<S>; private shell: Shell; private view: View<S>; private voice: Voice; private store: LearnerStore; private watch: string;
  private vol: Record<Bus, number>;
  private mutedOn: boolean;
  private lit: string | null = null;
  private sections: SectionSpec[];
  /** The lesson beat the open section was entered from, and how to enter it again (null: none, e.g. a reload inside the section). */
  private origin: { name: string; enter: EnterOptions } | null = null;
  readonly markers: MarkerRouter;
  constructor(p: PlayerParts<S>) {
    this.d = p.d; this.shell = p.shell; this.view = p.view; this.voice = p.voice; this.store = p.store; this.watch = p.watch ?? 'watch';
    this.markers = p.markers ?? new MarkerRouter([]);
    this.sections = p.sections ?? [];
    if (this.sections.length) p.d.events.on('beat', (e) => this.entered(e.name));
    const pr = p.store.prefs();
    this.vol = { voice: pr.voice ?? 1, sfx: pr.sfx ?? 1 };
    this.mutedOn = !!pr.muted;
    this.sound();
    p.shell.captions(pr.cc ?? true);
  }
  toggle(): void { this.d.beats.toggle(); this.d.wake(); }
  back(): void { this.d.beats.cur?.back?.(); this.d.wake(); }
  fwd(): void { this.d.beats.cur?.fwd?.(); this.d.wake(); }
  /** Land on the sentence holding watch second `t`; from a play beat this is a re-watch that keeps the beat's snapshot. */
  seek(t: number): void {
    const cur = this.d.beats.cur;
    if (cur?.timed && cur.seek) cur.seek(t); else this.d.beats.back(this.watch, t);
    this.d.wake();
  }
  scrub(t: number): void { const cur = this.d.beats.cur; if (cur?.timed) cur.scrub?.(t); this.d.wake(); }
  chapter(c: Chapter): void {
    if (c.t !== undefined) { this.seek(c.t); return; }
    if (!c.beat || !c.reached) return;
    if (!this.d.beats.returnTo(c.beat)) this.d.go(c.beat);
    this.d.wake();
  }
  hint(): boolean { const ok = !!this.d.beats.cur?.hint?.(); this.d.wake(); return ok; }
  /** Give up on the open case: its answer is shown. */
  giveUp(): boolean { const ok = !!this.d.beats.cur?.giveUp?.(); this.d.wake(); return ok; }
  /** Back from a section into the lesson: where the learner left it, else the lesson's own point (the end once finished, else the first chapter not done). */
  lesson(beat: string): void {
    const d = this.d, s = sectionOf(this.sections, beat)!, list = d.chapters();
    const p = this.origin ?? lessonPoint(list, d.furthest, isFinished(list, d.completed), s.back.to, this.watch);
    d.go(p.name, p.enter); d.wake();
  }
  /** Follow the open beat: a section entered from the lesson remembers where; the section head shows only inside a section. */
  private entered(name: string): void {
    const d = this.d, left = d.beats.left;
    if (!sectionOf(this.sections, name)) this.origin = null;
    else if (left && !sectionOf(this.sections, left.name)) this.origin = left;
    const v = sectionView(this.sections, name, (b) => { d.go(b); d.wake(); });
    if (v) v.back.go = () => this.lesson(name);
    this.shell.section(v);
  }
  /** Close the open sheet, else the open callout, else the end card; false when nothing was open. */
  close(): boolean {
    if (this.shell.pops.close()) return true;
    if (this.d.opened === null) return this.shell.closeEnd();
    this.d.explain(null); return true;
  }
  /**
   * A tap on the drawing (Chain of Responsibility): the open note's buttons, then a numbered marker (opens its callout; the open one
   * closes), then the beat (a control), then a part's body (nothing), then bare paper (closes the callout).
   */
  tap(px: number, py: number, wx: number, wy: number, fine = true): void {
    const n = this.d.opened ? this.view.noteAt?.(px, py) : null;
    if (n === 'hear') { this.d.hear(this.d.opened!); return; }
    if (n === 'close') { this.d.explain(null); return; }
    if (n === 'inside') return;
    const m = this.markers.hit(px, py, this.view, fine);
    if (m) { this.d.explain(m.term === this.d.opened ? null : m.term); return; }
    if (this.d.beats.cur?.tap?.(wx, wy)) { this.d.wake(); return; }
    if (this.d.spots.peek(wx, wy)) return;
    this.d.explain(null);
  }
  /** The pointer rests on a numbered marker: the help cursor and a faint outline of its part; anywhere else, nothing (screen px, null: left). */
  hover(px: number | null, py: number | null): void {
    const m = px === null || py === null ? null : this.markers.hit(px, py, this.view), part = m?.part ?? null;
    this.view.canvas.style.cursor = part ? 'help' : '';
    if (part === this.lit) return;
    this.lit = part;
    this.d.light(part);
  }
  volume(bus: Bus, v: number): void { this.vol[bus] = v; this.store.setPrefs(bus === 'voice' ? { voice: v } : { sfx: v }); this.sound(); }
  mute(): void { this.mutedOn = !this.mutedOn; this.store.setPrefs({ muted: this.mutedOn }); this.sound(); }
  private sound(): void {
    for (const b of ['voice', 'sfx'] as Bus[]) this.voice.volume(b, this.mutedOn ? 0 : this.vol[b]);
    this.shell.muted(this.mutedOn, this.vol);
  }
  cc(on: boolean): void { this.store.setPrefs({ cc: on }); }

  /** Connect the chrome, the pointer and the keys to these actions. */
  bind(): void {
    const { d, shell, view } = this;
    shell.on = {
      toggle: () => this.toggle(), replay: () => d.go(this.watch), back: () => this.back(),
      scrub: (t) => this.scrub(t), seek: (t) => this.seek(t),
      open: (id) => d.explain(id), hear: () => { if (d.opened) d.hear(d.opened); }, close: () => d.explain(null),
      chapter: (c) => this.chapter(c), say: () => this.back(), hint: () => { this.hint(); }, giveUp: () => { this.giveUp(); },
      volume: (b, v) => this.volume(b, v), mute: () => this.mute(), cc: (on) => this.cc(on),
    };
    shell.sections(this.sections.map((x) => ({ name: x.name, note: x.note, tabs: x.tabs.map((t) => ({ label: t.label, go: () => { d.go(t.beat); d.wake(); } })) })));
    d.events.on('beat', (e) => shell.beat(e.name));
    const router = new PointerRouter(view.canvas, view, d.hands);
    router.onGrab = (g) => { d.activeHand = d.hands.indexOf(g); if (d.opened) d.explain(null, false); d.beats.touched(); };
    router.onActivity = () => d.wake();
    router.onTap = (px, py, wx, wy, _g, fine) => this.tap(px, py, wx, wy, fine);
    router.onHover = (px, py) => this.hover(px, py);
    const zoom = view.zoom ? new ZoomControl(view.zoom, view.canvas, view.el.ownerDocument.getElementById('shell') ?? view.el, () => d.wake(true)) : null;
    zoom?.attach(router);
    const keys: KeyActions = {
      toggle: () => this.toggle(), back: () => this.back(), fwd: () => this.fwd(), home: () => this.seek(0),
      transcript: () => shell.sideTab('transcript'), help: () => shell.pop('keys'),
      cc: () => { const on = !shell.captioned; shell.captions(on); this.cc(on); }, hint: () => { this.hint(); },
      mute: () => this.mute(), close: () => this.close(),
      zoom: zoom ? (dir) => { if (dir) zoom.step(dir); else zoom.reset(); } : undefined, commit: () => { this.d.beats.cur?.commit?.(); this.d.wake(); },
    };
    bindKeys(d, keys);
  }
}

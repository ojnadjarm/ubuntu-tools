import { AudioClock, ManualClock, PerfClock, type Clock } from './core/clock';
import { VoicePlayer, NullVoice, type Voice } from './audio/voice';
import { LearnerStore, LocalStorage, MemoryStorage } from './core/store';
import { Director, type Easing } from './unit/director';
import { chapterAt, chapterSpecs } from './unit/chapters';
import { isFinished, landing, restore, track, type FinishedOffer, type ResumePoint, type TrackOptions } from './unit/resume';
import { Player } from './player';
import type { Beat } from './unit/beats';
import type { Control, UnitDef, View } from './unit/ports';
import type { Hotspot } from './play/hotspots';
import { MarkerRouter, type Marker } from './play/markers';
import type { UnitBundle } from './content/types';
import type { Shell } from './shell/shell';
import type { SectionSpec } from './unit/sections';

/** Numbers the headless tools read (`window.__probe`); a style may add its own fields. */
export interface Probe { ready: number; frames: number; fw: number[]; longtasks: number[]; [k: string]: unknown }

const win = globalThis as unknown as Record<string, unknown>;
export const probe: Probe = { ready: 0, frames: 0, fw: [], longtasks: [] };
win.__probe = probe;
if (typeof document !== 'undefined') new PerformanceObserver((l) => { for (const e of l.getEntries()) probe.longtasks.push(Math.round(e.duration)); }).observe({ type: 'longtask', buffered: true });

export interface BootOptions<S extends object> {
  unit: UnitDef<S>;
  bundle: UnitBundle;
  view: View<S>;
  shell: Shell;
  controls?: Control<S>[];
  /** Parts of the drawing: where a callout's dot sits, and what is a part's body rather than bare paper (a tap on a body opens nothing). */
  hotspots?: Hotspot[];
  /** The numbered badges: the only targets a click or tap opens a callout from, and the only ones a hover answers. */
  markers?: Marker[];
  /** Every beat by name; `watch` is where the unit starts and Replay returns. */
  beats(d: Director<S>): Record<string, Beat>;
  /** State as the watch leaves it, for `?beat=` jumps and `__rec.go`. */
  after?(): Partial<S>;
  /** State shown behind the Begin card. */
  opening?: Partial<S>;
  easing?: Easing<S>;
  /** Remember progress and preferences under this unit id (localStorage `plates:v1:progress`); omitted: preferences only, in memory. */
  progress?: TrackOptions;
  /** Parts of the unit outside its chapters (Practice): a head with a tab per beat and the way back; never listed as chapters. */
  sections?: SectionSpec[];
  /** The landing card of a finished unit (its line and ways on); without it a finished unit lands on Continue / Start over. */
  finished?: FinishedOffer;
}

/** Load the watch chapter the learner starts in (none when resuming a play beat), then prefetch the rest of the watch in order, then every line. */
function loadFirst<S extends object>(d: Director<S>, voice: VoicePlayer, resume: ResumePoint | null): Promise<void> {
  const order = d.unit.watch.order, t = resume ? (resume.beat === 'watch' ? resume.enter.at ?? 0 : null) : 0;
  const ch = t === null ? undefined : chapterAt(d.chapters(), t);
  const first = t === null ? [] : chapterSpecs(d.bundle.spec, d.offsets).find((c) => c.id === ch?.id)?.clips ?? order.slice(0, 1);
  const i = first.length ? order.indexOf(first[0]) : 0;
  const rest = [...order.slice(i), ...order.slice(0, i), ...Object.keys(d.bundle.cues.clips)].filter((id, k, l) => !first.includes(id) && l.indexOf(id) === k);
  const loading = voice.load(first);
  void loading.then(() => voice.prefetch(rest));
  return loading;
}

/** Composition root for one unit: URL modes (`?t=` frozen, `?mute`, `?fast=` with `?mute`, `?beat=`), clock and voice, store and resume, Begin, input, resize, test hooks. */
export function boot<S extends object>(o: BootOptions<S>): { d: Director<S>; clock: Clock; voice: Voice; player: Player<S>; started: Promise<void> } {
  const q = new URLSearchParams(location.search);
  const frozen = q.has('t'), mute = q.has('mute') || frozen, jump = q.get('beat');
  const { shell, view } = o;
  const voice: Voice = mute ? new NullVoice() : new VoicePlayer(o.bundle);
  const clock = frozen ? new ManualClock(Number(q.get('t') ?? 0), false) : voice.ctx ? new AudioClock(voice.ctx) : new PerfClock();
  const d = new Director({ unit: o.unit, bundle: o.bundle, view, voice, clock, shell, controls: o.controls, hotspots: o.hotspots }, o.easing);
  d.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (mute) d.rate = Math.max(1, Number(q.get('fast')) || 1);
  d.onFrame = (ms) => { probe.frames++; if (probe.fw.length < 5000) probe.fw.push(+ms.toFixed(2)); };
  for (const h of d.hands) h.onDetent = () => voice.fx('detent', 0.8);
  for (const [name, beat] of Object.entries(o.beats(d))) d.beats.add(name, beat);

  const store = new LearnerStore(o.progress && !frozen ? new LocalStorage() : new MemoryStorage());
  const resume: ResumePoint | null = o.progress && voice.ctx && !jump ? restore(d, store, o.progress, o.sections) : null;
  const offer = landing(resume, !!resume && isFinished(d.chapters(), d.completed), o.finished);
  if (o.progress) {
    const tr = track(d, store, o.progress);
    addEventListener('pagehide', () => tr.flush());
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') tr.flush(); });
  }
  const loading = voice instanceof VoicePlayer ? loadFirst(d, voice, resume) : Promise.resolve();
  const begun = voice.ctx ? shell.begin(offer) : null;
  const player = new Player({ d, shell, view, voice, store, markers: new MarkerRouter(o.markers ?? []), sections: o.sections });
  player.bind();
  new ResizeObserver(() => { view.resize(); d.wake(true); }).observe(view.el);
  const t0 = performance.now();
  view.prepare?.();
  probe.compileMs = Math.round(performance.now() - t0);

  const after = (): void => { Object.assign(d.s, o.after?.() ?? {}); };
  /** Open the unit on the landing card's choice: `continue` resumes, `start` plays the watch from 0, any other value is a beat. */
  const start = (choice: string): void => {
    if (jump && jump !== 'watch') { after(); d.go(jump); }
    else if (choice === 'continue' && resume) { if (resume.beat !== 'watch') after(); d.go(resume.beat, resume.enter); }
    else if (choice !== 'continue' && choice !== 'start' && choice !== 'watch') { after(); d.go(choice); }
    else d.go('watch');
  };
  /** Frozen stills and sweeps: land exactly on watch second `t`, as a seek does, so no chapter stop catches the jump. */
  const watchAt = (t: number): void => {
    if (d.beats.name !== 'watch') d.go('watch');
    const w = d.beats.cur as { seek?(t: number, play?: boolean, exact?: boolean): void } | null;
    if (w?.seek) w.seek(t, true, true); else (clock as ManualClock).set(t);
    d.wake(true);
  };
  win.__d = d;
  win.__rec = {
    watch: watchAt,
    go: (b: string) => { after(); d.go(b); },
    turn: (i: number, n: number) => { d.hands[i].turn(n); d.wake(); },
    commit: () => { const ok = !!d.beats.cur?.commit?.(); d.wake(); return ok; },
    tap: (wx: number, wy: number) => { const ok = !!d.beats.cur?.tap?.(wx, wy); d.wake(); return ok; },
    hint: () => player.hint(),
    seek: (t: number) => player.seek(t),
    explain: (id: string | null) => d.explain(id),
    offsets: d.offsets, duration: d.tl.duration(),
  };
  probe.duration = d.tl.duration();
  win.__seek = (t: number) => (win.__rec as { watch(t: number): void }).watch(t);

  const started = (async () => {
    if (frozen) { d.reach(d.tl.duration()); shell.live(); start('start'); if (d.beats.name === 'watch') watchAt(Number(q.get('t'))); else (clock as ManualClock).set(Number(q.get('t'))); }
    else if (voice.ctx && begun) {
      Object.assign(d.s, o.opening ?? {});
      d.wake(true);
      const choice = await begun; shell.live(); await voice.ctx.resume(); await loading;
      start(choice);
    } else { shell.live(); start('start'); }
    d.wake(true);
    requestAnimationFrame(() => requestAnimationFrame(() => { probe.ready = performance.now(); win.__ready = true; }));
  })();
  return { d, clock, voice, player, started };
}

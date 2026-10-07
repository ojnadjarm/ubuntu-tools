import 'cutaway-kit/plate.css';
import { Ink, Stage, OnDemand, stateKey, loadFonts, layoutClips, CueBinder, Narration, AudioClock, ManualClock, PerfClock, DialHand, PointerRouter, Shell, Captions, type Clock, type CueSheet, type UnitSpec } from 'cutaway-kit';
import { LOOK } from './look.ts';
import { SHOTS, CASING } from './layout.ts';
import { RegulatorPlate } from './plate.ts';
import { initialState } from './state.ts';
import { buildScript, LEAD, ORDER } from './script.ts';

/** Composition root: builds every collaborator once; `?t=<s>` freezes the narration axis for stills, `?mute` plays without audio. */
const q = new URLSearchParams(location.search);
const frozen = q.has('t'), mute = q.has('mute') || frozen;
const probe = { ready: 0, plateMs: 0, frames: 0, duration: 0, fw: [] as number[], longtasks: [] as number[] };
const win = window as unknown as Record<string, unknown>;
win.__probe = probe;
new PerformanceObserver((l) => { for (const e of l.getEntries()) probe.longtasks.push(Math.round(e.duration)); }).observe({ type: 'longtask', buffered: true });

const BUNDLE = 'bundles/s00/';
const [, cues, spec] = await Promise.all([loadFonts(), fetch(BUNDLE + 'cues.json').then((r) => r.json() as Promise<CueSheet>), fetch(BUNDLE + 'unit.json').then((r) => r.json() as Promise<UnitSpec>)]);
const shell = new Shell(document.getElementById('shell')!, {
  num: '00', name: 'Regulator', eyebrow: 'Plate 0.', title: 'The Regulator',
  lede: 'A sectioned instrument, drawn and named as you listen. Then the dial is yours.', keys: 'Space pauses. Arrow keys turn the dial.',
});
const ink = new Ink(LOOK);
const stage = new Stage(document.getElementById('stage')!, ink);
stage.setShots(Object.values(SHOTS));
stage.resize();
const t0 = performance.now();
const plate = new RegulatorPlate(ink);
probe.plateMs = Math.round(performance.now() - t0);
stage.scene.add(plate.root);

const s = initialState();
const { offsets } = layoutClips(cues, ORDER, LEAD, 0.9);
const script = buildScript(s, new CueBinder(cues, offsets));
probe.duration = script.duration();
const captions = new Captions(cues, spec, offsets);
const voice = mute ? null : new Narration(cues, BUNDLE);
const clock: Clock = frozen ? new ManualClock(Number(q.get('t'))) : voice ? new AudioClock(voice.ctx) : new PerfClock();
const hand = new DialHand(plate.dial, stage);
hand.enabled = false;
new PointerRouter(stage.renderer.domElement, stage, [hand]).onActivity = () => loop.wake();

let last = '', flowRun = 0;
const loop = new OnDemand((dt, force) => {
  const t = clock.now(), watching = t < script.duration();
  if (watching) script.seek(t);
  else {
    if (!hand.enabled) { script.seek(script.duration()); hand.enabled = true; hand.place(s.rate); shell.status('Your turn'); shell.pausable(false); }
    s.rate = hand.update(dt);
  }
  shell.caption(watching ? captions.at(t) : '');
  const key = stateKey(s), changed = key !== last;
  last = key;
  flowRun = changed || (watching && clock.playing()) ? 2.5 : Math.max(0, flowRun - dt);
  if (!changed && !force && flowRun <= 0 && !(watching && clock.playing())) return false;
  plate.apply(s, dt, flowRun > 0);
  stage.frame({ x: s.camX, y: s.camY, w: s.camW, h: s.camH });
  const [sw, sh] = stage.span();
  plate.lamp.set(s.lampX, s.lampY, s.lampOn, Math.max(sw, sh));
  plate.veil.set(stage.cx, stage.cy, sw, sh, s.exposure);
  stage.render();
  return true;
});
loop.onFrame = (ms) => { probe.frames++; if (probe.fw.length < 5000) probe.fw.push(+ms.toFixed(2)); };
new ResizeObserver(() => { stage.resize(); loop.wake(true); }).observe(stage.el);

/** Pause and resume keep audio and picture on one axis: both restart from the clock's time. */
const toggle = (): void => {
  const t = clock.now();
  if (t >= script.duration()) return;
  if (clock.playing()) { clock.stop(); voice?.stop(); } else { voice?.play(offsets, t); clock.start(t); }
  shell.playing(clock.playing()); loop.wake(true);
};
const replay = (): void => { hand.enabled = false; shell.status('Watch'); shell.pausable(true); voice?.play(offsets, 0); clock.start(0); shell.playing(true); loop.wake(true); };
shell.onToggle = toggle;
shell.onReplay = replay;
addEventListener('keydown', (e) => {
  if (e.key === ' ' && !(e.target instanceof HTMLButtonElement)) { e.preventDefault(); toggle(); return; }
  if (!hand.enabled) return;
  if (e.key === 'ArrowRight' || e.key === 'ArrowUp') hand.turn(1); else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') hand.turn(-1); else return;
  loop.wake();
});
stage.renderer.compile(stage.scene, stage.camera);

win.__seek = (t: number) => { (clock as ManualClock).set(t); loop.wake(true); };
/** The casing on screen, clipped to the viewport: `tools/shot.mjs` runs the look gate inside it. */
win.__casingPx = () => {
  const [a, b] = stage.toScreen(CASING[0], CASING[3]), [c, d] = stage.toScreen(CASING[2], CASING[1]);
  return [Math.max(0, a), Math.max(0, b), Math.min(stage.W, c), Math.min(stage.H, d)];
};
requestAnimationFrame(() => requestAnimationFrame(() => { probe.ready = performance.now(); }));
if (frozen) shell.live();
else {
  loop.wake(true);
  await shell.begin();
  if (voice) { await voice.ctx.resume(); await voice.load(); voice.play(offsets, 0); }
  clock.start(0);
}
loop.wake(true);

if (import.meta.hot) import.meta.hot.accept('./look.ts', (m) => { if (m) { ink.paint(m.LOOK); stage.renderer.setClearColor(m.LOOK.paper); loop.wake(true); } });

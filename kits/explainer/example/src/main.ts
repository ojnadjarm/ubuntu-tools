import { boot, probe, loadBundle, Shell, type UnitSpec } from 'explainer-kit';
import { CutawayView, cutawayEasing } from 'explainer-kit/cutaway';
import { THEME } from './plate/theme';
import { Ink } from './plate/ink';
import { Stage } from './plate/stage';
import { Plate } from './plate/plate';
import { afterWatch, SHOTS } from './units/a01/watch';
import { A01, beats, controls } from './units/a01/unit';
import spec from '../content/a01.unit.json';

/** Composition root: the Cutaway plate (style) and unit A01 (content) handed to the explainer engine. */
const FONTS: [string, string, string, string][] = [
  ['Plex Cond', '400', 'normal', 'ibm-plex-sans-condensed-latin-400-normal'], ['Plex Cond', '500', 'normal', 'ibm-plex-sans-condensed-latin-500-normal'],
  ['Plex Cond', '600', 'normal', 'ibm-plex-sans-condensed-latin-600-normal'], ['Plex Mono', '500', 'normal', 'ibm-plex-mono-latin-500-normal'],
  ['Caslon', '400', 'normal', 'libre-caslon-text-latin-400-normal'], ['Caslon', '400', 'italic', 'libre-caslon-text-latin-400-italic'],
];
const fonts = (): Promise<void[]> => Promise.all(FONTS.map(async ([f, w, st, u]) => {
  const ff = new FontFace(f, `url(fonts/${u}.woff2)`, { weight: w, style: st }); await ff.load(); document.fonts.add(ff);
}));
Object.assign(probe, { backend: 'webgl2', accentDrawn: '' });

const [, bundle] = await Promise.all([fonts(), loadBundle('bundles/a01/', spec as UnitSpec)]);
const ink = new Ink(THEME);
const stage = new Stage(document.getElementById('stage')!, ink);
stage.setShots(Object.values(SHOTS).map((b) => ({ x: b.camX, y: b.camY, w: b.camW, h: b.camH })));
let t0 = performance.now();
stage.resize();
probe.resizeMs = Math.round(performance.now() - t0);
t0 = performance.now();
const plate = new Plate(ink);
probe.plateMs = Math.round(performance.now() - t0);
stage.scene.add(plate.root);
const shell = new Shell(document.getElementById('shell')!, {
  num: '01', name: 'Neuron', eyebrow: 'Plate I · Instrument 01', title: 'What a neural network is',
  lede: 'A narrated engineering plate, drawn with its casing cut away. Watch it work, then tune it by hand. About ninety seconds, with sound.',
  keys: 'Drag a dial to turn it. Arrow keys turn the lit dial.', endEyebrow: 'End of the opening', endTitle: 'Next in the full unit: race the tuner',
});
const view = new CutawayView(stage, plate);
const { d } = boot({ unit: A01, bundle, view, shell, controls: controls(view), beats, after: afterWatch, opening: { ...SHOTS.open, exposure: 0.35 }, easing: cutawayEasing });
const count = d.onFrame;
d.onFrame = (ms) => { count(ms); probe.accentDrawn = ink.theme.signal; };

if (import.meta.hot) import.meta.hot.accept('./plate/theme.ts', (m) => { if (m) { ink.paint(m.THEME); stage.renderer.setClearColor(m.THEME.paper); d.wake(true); } });

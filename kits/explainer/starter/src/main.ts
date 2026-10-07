import { boot, probe, loadBundle, partMarkers, Shell, type UnitSpec } from 'explainer-kit';
import { CutawayView, cutawayEasing } from 'explainer-kit/cutaway';
import { Ink, Stage, THEME, loadFonts } from 'cutaway-kit';
import { BiasPlate } from './plate/plate';
import { afterWatch } from './units/a02/watch';
import { CASING, SHOTS } from './units/a02/layout';
import { A02, HOTSPOTS, beats, controls } from './units/a02/unit';
import spec from '../content/a02.unit.json';

/** Composition root: cutaway-kit parts (style) and unit A02 (content) handed to the explainer engine. */
Object.assign(probe, { backend: 'webgl2' });
const [, bundle] = await Promise.all([loadFonts(), loadBundle('bundles/a02/', spec as UnitSpec)]);
const ink = new Ink(THEME);
const stage = new Stage(document.getElementById('stage')!, ink);
stage.setShots(Object.values(SHOTS));
stage.resize();
const t0 = performance.now();
const plate = new BiasPlate(ink);
probe.plateMs = Math.round(performance.now() - t0);
stage.scene.add(plate.root);
const shell = new Shell(document.getElementById('shell')!, {
  num: '02', name: 'Bias', eyebrow: 'Plate II · Instrument 02', title: 'The dial with no input',
  lede: 'Why a neuron needs a bias: a narrated engineering plate, then two dials in your hands and a small puzzle. About two minutes, with sound.',
  keys: 'Drag a dial to turn it. Arrow keys turn the lit dial; Up and Down pick the other one.', tip: 'Tap a circled number to see what the part is and its numbers. Press ? for every key.',
  endEyebrow: 'End of the unit', endTitle: 'Next: many neurons, wired together', endLede: 'Any chapter below plays again.',
});
const view = new CutawayView(stage, plate);
boot({
  unit: A02, bundle, view, shell, controls: controls(plate.dials, view), hotspots: HOTSPOTS, markers: partMarkers(bundle.spec.parts ?? [], (n) => plate.balloonAt(n), 15), beats, after: afterWatch,
  opening: { exposure: 0.35 }, easing: cutawayEasing, progress: { unit: 'A02', states: { drive: 'driven', ex: 'played' } },
});
/** The casing on screen, clipped to the viewport: `tools/shot.mjs` runs the look gate inside it. */
(window as unknown as Record<string, unknown>).__casingPx = () => {
  const [a, b] = stage.toScreen(CASING[0], CASING[3]), [c, e] = stage.toScreen(CASING[2], CASING[1]);
  return [Math.max(0, a), Math.max(0, b), Math.min(stage.W, c), Math.min(stage.H, e)];
};

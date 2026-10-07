// Check every shot in src/layout.ts; for a failing one print the nearest fault-free box. Usage: node tools/fit-shots.ts [shot=id,id …]
import { framingFaults, fitShot, DESKTOP } from 'cutaway-kit/framing.ts';
import { SHOTS, WHOLE } from '../src/layout.ts';

const need: Record<string, string[]> = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, v = ''] = a.split('='); return [k, v.split(',').filter(Boolean)]; }));
for (const [name, b] of Object.entries(SHOTS)) {
  const cut = framingFaults({ [name]: b }, WHOLE, DESKTOP).map((f) => f.split(' cuts ')[1]);
  const fit = fitShot(b, WHOLE, need[name] ?? [], DESKTOP);
  if (!cut.length && JSON.stringify(fit) === JSON.stringify(b)) { console.log(`${name}: OK`); continue; }
  console.log(`${name}: cuts ${[...new Set(cut)].join(', ') || '—'} (fine only if hidden while held: npm test) · nearest whole box ${fit ? JSON.stringify(fit) : 'none within ±300 / 0.8–1.4×'}`);
}

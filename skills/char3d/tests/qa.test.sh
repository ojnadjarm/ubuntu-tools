#!/usr/bin/env bash
# QA judge without Blender: a synthetic clean walk passes; injected motion, shot and AAA asset-gate faults fail where injected; contact sheet is written.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
export C3D_SCRIPTS=$here/scripts C3D_SPEC=$here/specs/darksaddler.json QA_OUT=$out SHEET_TO=${QA_SHEET_TO:-}

python3 - <<'PY'
import json, os, shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, os.environ['C3D_SCRIPTS'])
from c3d import qa_metrics as q

FPS, CYCLE, N = 30, 36, 72
ROLES = ['foot.L', 'foot.R', 'hand.L', 'hand.R', 'head', 'hips', 'root']
out = Path(os.environ['QA_OUT']); (out / 'qa').mkdir()


def mj(u):
    return 10 * u**3 - 15 * u**4 + 6 * u**5


def walk(stride=0.6, stance=0.6):
    """Two 1.2 s cycles at 30 fps with root motion: planted feet, min-jerk swings, swinging hands, bobbing hips/head."""
    t = np.arange(N + 1)
    J = np.zeros((N + 1, len(ROLES), 3))
    for k, off in ((0, 0.0), (1, 0.5)):
        ph = t / CYCLE + off
        u = np.clip((ph % 1 - stance) / (1 - stance), 0, 1)
        J[:, k] = np.stack([np.full(N + 1, 0.1 - 0.2 * k), -stride * (np.floor(ph) + mj(u) - off),
                            0.06 + 0.08 * np.sin(np.pi * u) ** 2], 1)
    w = 2 * np.pi * t / CYCLE
    for k, (x, z, sw, bob) in enumerate(((0.27, 0.9, 0.12, 1), (-0.27, 0.9, -0.12, 1), (0, 1.62, 0, 1),
                                         (0, 0.95, 0, 1), (0, 0, 0, 0)), 2):
        J[:, k] = np.stack([np.full(N + 1, x), -stride / CYCLE * t + sw * np.sin(w), z + bob * 0.018 * np.cos(2 * w)], 1)
    return J, J[:, :2, 2].min(1) - 0.06


def lids(blinks, stuck=None):
    t = np.arange(1, N + 2)
    v = np.full(N + 1, 0.43)
    for b in blinks:
        v = np.minimum(v, 0.43 * np.clip(np.abs(t - b) / 3, 0, 1))
    L = np.stack([v, v], 1)
    if stuck:
        L[stuck - 1, 1] = 0.25
    return L


def clip(cid, J=None, min_z=None, loop=True, self_x=None, depth=None, lid=None, blinks=(), **extra):
    J0, z0 = walk()
    path = out / 'qa' / f'{cid}.npz'
    np.savez(path, joints=J0 if J is None else J, roles=np.array(ROLES), min_z=z0 if min_z is None else min_z, fps=FPS,
             contacts=np.array(['foot.L', 'foot.R']), loop=loop, start=1, frames=np.arange(1, N + 2),
             self_x=np.zeros((N + 1, 2), int) if self_x is None else self_x, self_x_parts=np.array(['body', 'robe']),
             depth=np.zeros((N + 1, 3)) if depth is None else depth,
             depth_parts=np.array(['robe', 'beard', 'staff.shaft']),
             lid=lids([20, 50]) if lid is None else lid, eyes=np.array(['eye.L', 'eye.R']), blinks=np.array(blinks, int),
             **extra)
    return f'qa:{cid}', str(path)


J, z = walk()
slide = J.copy(); slide[40:, 0, 1] -= 0.006 * np.clip((np.arange(40, N + 1) - 40) / 5, 0, 1)   # frames 41-46, foot.L plant
pen = z.copy(); pen[40] = -0.008                                                             # frame 41
pop = J.copy(); pop[30, 3, 0] += 0.01                                                        # frame 31, hand.R
flt = z.copy(); flt[5:9] += 0.008                                                            # frames 6-9
seam = J.copy(); seam[N, 4, 0] += 0.01                                                       # loop gap, head
sx = np.zeros((N + 1, 2), int); sx[12, 1] = 4                                                # frame 13, robe
dp = np.zeros((N + 1, 3)); dp[18, 0] = 0.008                                                 # frame 19, robe
tele = J.copy(); tele[30:50, 3, 2] -= 0.25                                                   # frames 31 and 51: steps at declared impacts
g0 = np.array([[0.0, 0.0, 0.6], [0.0, 0.02, 0.68]]); gr = np.repeat(g0[None], N + 1, 0)
gr[40:, :, 0] += 0.008                                                                      # frame 41, hand off the staff
soles = np.stack([J[:, 0] + [0, 0.1, -0.06], J[:, 0] + [0, -0.1, -0.06], J[:, 1] + [0, 0.1, -0.06],
                  J[:, 1] + [0, -0.1, -0.06]], 1)
soles[40:, 0, 1] -= 0.006 * np.clip((np.arange(40, N + 1) - 40) / 5, 0, 1)                  # heel.L slides, toe joints planted
stand = np.repeat(J[:1], N + 1, 0)
late = stand.copy(); late[-2:, 2, 0] += 0.02                                                 # one-shot ends 20 mm off idle
sole_kw = dict(soles=soles, sole_names=np.array(['heel.L', 'ball.L', 'heel.R', 'ball.R']))
files = dict([clip('clean'), clip('inferred_blinks'), clip('slide', J=slide, loop=False), clip('pen', min_z=pen),
              clip('pop', J=pop), clip('float', min_z=flt), clip('seam', J=seam), clip('selfx', self_x=sx),
              clip('depth', depth=dp), clip('lid', lid=lids([20, 50], stuck=50), blinks=[20, 50]),
              clip('tele', J=tele, impacts=np.array([31, 51])), clip('grip', grip=gr, grip_rest=g0),
              clip('heel', **sole_kw), clip('idle', J=stand, min_z=np.zeros(N + 1)),
              clip('oneshot', J=late, min_z=np.zeros(N + 1), loop=False)])
pn = np.zeros((N + 1, 5)); pn[24, 0] = 0.006; hv = np.zeros(N + 1, bool); hv[[0, 24, 30, 60]] = True   # frame 25, beard-robe
files.update([clip('pairpen', pen=pn, heavy=hv, pen_pairs=np.array(['beard-robe', 'robe-body', 'layer-layer', 'hat-head',
              'staff-hand']), pen_probed=np.array([True, True, True, True, False]))])
for cid in ('clean', 'pen', 'pop', 'float', 'seam', 'selfx', 'depth', 'tele', 'grip', 'heel', 'idle', 'oneshot'):   # declared blinks everywhere but one clip
    d = dict(np.load(files[f'qa:{cid}'])); d['blinks'] = np.array([20, 50]); np.savez(files[f'qa:{cid}'], **d)

yy, xx = np.mgrid[0:90, 0:160]
disc = (xx - 80) ** 2 + (yy - 45) ** 2 < 30 ** 2
base = np.where(disc, 0.35 + 0.25 * (yy / 90), 0.05)
renders, shots = {}, {}
rng = np.random.default_rng(1)
for sid, img in (('ok', base), ('noisy', base + disc * rng.normal(0, 3 / 255, base.shape)), ('dark', base * 0.25),
                 ('hot', base + disc * 0.6)):
    p = out / f'{sid}.png'
    Image.fromarray((np.clip(np.repeat(img[..., None], 3, 2), 0, 1) * 255).round().astype(np.uint8)).save(p)
    renders[sid] = {'frames': 1, 'fps': FPS, 'size': [160, 90], 'file': str(p), 'mb': 0.01}
    shots[f'mask:{sid}'] = disc[None, ::2, ::2]
    shots[f'mask_frames:{sid}'] = np.array([0])
renders['big'] = {'frames': 30, 'fps': FPS, 'size': [160, 90], 'file': str(out / 'big.mp4'), 'mb': 25.0}
fr = np.full(30, 0.12); fr[4] = 0.02
shots['framing:wide'] = fr                                                                   # frame 5
shots['framing:closeup'] = np.full(30, 0.2)
np.savez(out / 'qa' / 'shots.npz', **shots)
files['qa_shots'] = str(out / 'qa' / 'shots.npz')

thr = json.load(open(os.environ['C3D_SPEC']))['qa']['thresholds']
thr.setdefault('pair_pen_mm', 0.0)
thr.setdefault('clip_pct', 0.5)   # research bar; add to specs that want the clip check
thr['plant_drift_cm'] = 0.5   # 0.6 cm slide vs a 0.5 cm probe bar; the 1 cm DarkSaddler bar is checked below
build = {'spec': {'id': 'synth', 'qa': {'thresholds': thr}, 'renders': [{'id': 'walk', 'kind': 'clip', 'clip': 'pop'}]},
         'renders': renders, 'files': files}
(out / 'build.json').write_text(json.dumps(build))

rep = q.evaluate(out)
by = {c['id']: c for c in rep['checks']}
expect = {'plant_drift:slide': ('foot.L', None), 'penetration:pen': (None, 41), 'jitter:pop': ('hand.R', 31),
          'float:float': (None, 6), 'loop_seam:seam': (None, 1), 'self_x:selfx': ('robe', 13),
          'garment_depth:depth': ('robe', 19), 'lid_visible:lid': (None, 50), 'framing:wide': (None, 5),
          'noise:noisy': (None, 1), 'exposure:dark': (None, 1), 'exposure:hot': (None, 1), 'clip:hot': (None, 1), 'mp4_size:big': (None, None),
          'joint_speed:tele': ('hand.R', 51), 'grip:grip': (None, 41), 'plant_drift:heel': ('heel.L', None),
          'clip_ends:oneshot': (None, 72), 'pen:beard-robe:pairpen': (None, 25), 'clip_ends:slide': (None, None),
          'jitter:oneshot': ('hand.L', 71)}   # the 20 mm end step is also a 1-frame pop: one-shot ends are judged   # slide: a walk track, not an idle one-shot
errors = []
failed = set(rep['summary']['failed'])
if failed != set(expect):
    errors.append(f'failed {sorted(failed)} != expected {sorted(expect)}')
for cid, (who, frame) in expect.items():
    c = by.get(cid, {})
    if frame is not None and c.get('frame') != frame:
        errors.append(f'{cid}: worst frame {c.get("frame")} != {frame} ({c})')
    if who and who not in (c.get('joint'), c.get('part')):
        errors.append(f'{cid}: blamed {c.get("joint") or c.get("part")} != {who}')
checks = {
    'slide onset f46': by['plant_drift:slide']['frames'][0] == 46,
    'slide value 0.6 cm': abs(by['plant_drift:slide']['value'] - 0.6) < 0.02,
    'pen value 0.8 cm': abs(by['penetration:pen']['value'] - 0.8) < 1e-6,
    'pop residual > 3 mm only at f31': by['jitter:pop']['frames'] == [31],
    'lid only peak 50': by['lid_visible:lid']['frames'] == [50] and by['lid_visible:lid']['blinks'] == [20, 50],
    'inferred blinks 20, 50': by['lid_visible:inferred_blinks']['blinks'] == [20, 50],
    'float frames 6-9': by['float:float']['frames'] == [6, 7, 8, 9],
    'seam gap 10 mm': abs(by['loop_seam:seam']['gap_mm'] - 10) < 1e-6,
    'clean clip all pass': all(c['pass'] for c in rep['checks'] if c['id'].endswith(':clean')),
    'clean clip 9 checks': sum(c['id'].endswith(':clean') for c in rep['checks']) == 9,
    'impact frames exempt from jitter': by['jitter:tele']['pass'] and by['joint_speed:tele']['frames'] == [31, 51],
    'pair pen 6 mm, 4 pairs, series': by['pen:beard-robe:pairpen']['value'] == 6.0 and by['pen:beard-robe:pairpen']['series_mm'] == {1: 0.0, 25: 6.0, 31: 0.0, 61: 0.0}
        and sum(c['id'].startswith('pen:') for c in rep['checks']) == 4,
    'grip slip 8 mm': abs(by['grip:grip']['value'] - 8) < 1e-6,
    'one-shot end 20 mm, start 0': by['clip_ends:oneshot']['end_mm'] == 20.0 and by['clip_ends:oneshot']['start_mm'] == 0.0,
    'noise ok < 1, noisy > 2': by['noise:ok']['value'] < 1 < 2 < by['noise:noisy']['value'],
    'exposure/clip ok pass': by['exposure:ok']['pass'] and by['clip:ok']['pass'],
    'sheet written': rep.get('sheet') and Path(rep['sheet']).stat().st_size > 5000,
    'CHECKS >= 10': len(q.CHECKS) >= 10 and set(q.NEEDS) == set(q.CHECKS),
}
errors += [k for k, ok in checks.items() if not ok]
thr['plant_drift_cm'] = 1.0
(out / 'build.json').write_text(json.dumps(build))
r2 = {c['id']: c for c in q.evaluate(out)['checks']}
if not r2['plant_drift:slide']['pass']:
    errors.append('0.6 cm slide should pass the 1 cm DarkSaddler bar')

# AAA asset gate: one clean texture set, one with 2 hot albedo rows, an x-biased normal map in sRGB; one thin-texel part.
ad = out / 'asset'; (ad / 'qa').mkdir(parents=True)
def png(name, rgb, rows=None):
    a = np.tile(np.array(rgb, np.uint8), (64, 64, 1))
    if rows:
        a[:2] = rows
    Image.fromarray(a).save(ad / name)
    return str(ad / name)
def tset(sid, albedo, normal, cs='Non-Color', hot=None):
    files = {'albedo': png(f'{sid}_a.png', albedo, hot), 'normal': png(f'{sid}_n.png', normal),
             'orm': png(f'{sid}_o.png', (255, 128, 0)), 'emissive': png(f'{sid}_e.png', (0, 0, 0))}
    space = {'albedo': 'sRGB', 'emissive': 'sRGB', 'normal': cs, 'orm': 'Non-Color'}
    return {'size': 2048, 'baked_size': 64, 'stub': True,
            'maps': {m: {'file': f, 'size': [64, 64], 'colourspace': space[m]} for m, f in files.items()}}
part = lambda **k: {'tris': 1000, 'quads_pct': 100.0, 'ngons': 0, 'hair': False, 'uv_outside': 0, 'uv_overlap': 0,
                    'texel_px_cm': 6.0, 'hero': False, **k}
asset = {'lod0_tris': 50000, 'quads_pct': 99.0, 'ngons': 0, 'max_influences': 4, 'unweighted': 0, 'uv_outside': 0,
         'uv_overlap': 0, 'skeleton': {'deform_bones': 3, 'deform_roots': 1, 'transforms_applied': True},
         'textures': {'robe': tset('robe', (90, 40, 120), (128, 128, 255)),
                      'bad': tset('bad', (90, 40, 120), (160, 128, 255), cs='sRGB', hot=(255, 255, 255))},
         'parts': {'body': part(texel_px_cm=12.0, hero=True), 'robe': part(texel_px_cm=3.0),
                   'beard.cards': part(hair=True, texel_px_cm=None)}}
def glb(roots):
    nodes = [{'children': [1, 2]}, {}, {}] if roots == 1 else [{'children': [1]}, {}, {}]
    js = json.dumps({'asset': {'version': '2.0'}, 'nodes': nodes, 'skins': [{'joints': [0, 1, 2]}]}).encode()
    js += b' ' * (-len(js) % 4)
    import struct
    (ad / 'g.glb').write_bytes(struct.pack('<III', 0x46546C67, 2, 20 + len(js)) + struct.pack('<II', len(js), 0x4E4F534A) + js)
    return str(ad / 'g.glb')
def judge(a, roots=1, shipped=None):
    (ad / 'qa' / 'asset.json').write_text(json.dumps(a))
    b = {'spec': {'id': 'asset', 'qa': {'thresholds': thr}, 'export': {'fbx': False}}, 'draft': True, 'renders': {},
         'files': {'qa_asset': str(ad / 'qa' / 'asset.json'), 'glb': glb(roots)},
         'stages': {'export': {} if shipped is None else {'max_influences': shipped}}}
    (ad / 'build.json').write_text(json.dumps(b))
    return {c['id']: c for c in q.evaluate(ad)['checks']}
gate = ('quads', 'uv_range', 'uv_overlap', 'texel_density', 'albedo_range', 'normal_map', 'texture_sets', 'skeleton')
r = judge(asset)
want_fail = {'texel_density', 'albedo_range', 'normal_map', 'texture_sets'}
for cid in gate:
    if cid not in r or r[cid]['pass'] == (cid in want_fail):
        errors.append(f'asset {cid}: {r.get(cid)}')
if r.get('texel_density', {}).get('part') != 'robe' or r.get('albedo_range', {}).get('set') != 'bad' \
        or abs(r['albedo_range']['value'] - 3.125) > 1e-3 or r.get('normal_map', {}).get('failed') != ['bad'] \
        or r.get('texture_sets', {}).get('problems') != ['bad.normal: sRGB != Non-Color']:
    errors.append(f'asset blame: {[r.get(k) for k in want_fail]}')
half = tset('half', (90, 40, 120), (128, 128, 255))
a = np.asarray(Image.open(half['maps']['albedo']['file'])).copy(); a[:, 32:] = 0
Image.fromarray(a).save(half['maps']['albedo']['file'])
n = np.asarray(Image.open(half['maps']['normal']['file'])).copy(); n[:, 32:] = 0
Image.fromarray(n).save(half['maps']['normal']['file'])
np.savez(ad / 'qa' / 'uv_half.npz', tris=np.array([[[0, 0], [0.5, 0], [0.5, 1]], [[0, 0], [0.5, 1], [0, 1]]], np.float32))
r3 = judge(dict(asset, textures={'half': dict(half, uv=str(ad / 'qa' / 'uv_half.npz'))}))
r4 = judge(dict(asset, textures={'half': half}))
if not (r3['albedo_range']['pass'] and r3['normal_map']['pass']) or r4['albedo_range']['pass'] or r4['normal_map']['pass']:
    errors.append(f"uv mask: covered {r3['albedo_range']} {r3['normal_map']} unmasked {r4['albedo_range']}")
if judge(dict(asset, textures={'half': dict(half, material=False)}))['texture_sets']['problems'] \
        != ['half: no material in the asset loads its maps']:
    errors.append('texture_sets: unwired set not named')
bad = dict(asset, quads_pct=90.0, uv_outside=5, uv_overlap=7)
r2 = judge(bad, roots=2)
for cid in ('quads', 'uv_range', 'uv_overlap', 'skeleton'):
    if r2.get(cid, {}).get('pass', True):
        errors.append(f'asset fault not caught: {cid} {r2.get(cid)}')
for src, shipped, ok in ((6, 4, True), (4, 6, False), (6, None, False)):
    if judge(dict(asset, max_influences=src), shipped=shipped)['influences']['pass'] != ok:
        errors.append(f'influences: source {src} shipped {shipped} should pass={ok}')
if os.environ['SHEET_TO']:
    shutil.copy(rep['sheet'], os.environ['SHEET_TO'])
if errors:
    print('FAIL qa:', *errors, sep='\n  ')
    sys.exit(1)
print(f"qa judge: {rep['summary']['checks']} results, {len(failed)} injected faults caught at their frames, "
      f"clean walk jitter {by['jitter:clean']['value']} mm, drift {by['plant_drift:clean']['value']} cm")
PY
if python3 "$here/scripts/c3d/qa_metrics.py" "$out" >/dev/null; then echo "FAIL: CLI exit 0 on failing build"; exit 1; fi
echo "PASS qa"

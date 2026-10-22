#!/usr/bin/env bash
# Motion lane: (1) numpy, no Blender: mocurves walk/idle/cast on DarkSaddler landmarks (plants, seams, SG residual,
# staff slam on the ground, free arm hanging, hands within arm reach); (2) darksaddler variant (walk + cast, flat bake) built --until motion:
# time, drift, ground.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
spec=${1:-$here/specs/darksaddler.json}
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

python3 - "$here/scripts" "$spec" <<'PY' || fail "motion curves"
import json, sys
import numpy as np
sys.path.insert(0, sys.argv[1])
from c3d import mocurves as mc
from c3d import qa_metrics as qm
s = json.load(open(sys.argv[2]))
lm = {'root': [0, 0, 0], 'hips': [0, 0, 0.99], 'spine': [0, 0.02, 1.14], 'chest': [0, 0.06, 1.34], 'neck': [0, -0.01, 1.54],
      'head': [0, -0.03, 1.63], 'jaw': [0, -0.05, 1.63], 'eye.L': [0.03, -0.12, 1.66], 'eye.R': [-0.03, -0.12, 1.66],
      'hand.L': [0.47, -0.2, 1.14], 'hand.R': [-0.47, -0.2, 1.14], 'foot.L': [0.18, 0.01, 0.07],
      'foot.R': [-0.18, 0.01, 0.07], 'toe.L': [0.19, -0.14, 0.03], 'toe.R': [-0.19, -0.14, 0.03]}
legs = {k: (np.array([0.126 * v, 0, 0.96]), 0.89) for k, v in mc.SIDES.items()}
tip = np.array([0.47, -0.2, 0.0])
rest = mc.Rest(lm, legs, {'hand': 'hand.L', 'tip': tip, 'verts': tip + np.outer(np.linspace(0, 1.9, 20), [0, 0, 1]),
                          'bone': 'prop_staff'})
sg = np.linalg.pinv(np.vander(np.arange(-3, 4), 4, increasing=True))[0]
fps, rep = s['motion']['fps'], {}
for clip in s['motion']['clips']:
    if clip['type'] not in mc.GENERATORS:
        continue
    poses, meta = mc.GENERATORS[clip['type']](rest, clip, fps, s.get('face', {}))
    Ds = [mc.solve(rest, p) for p in poses]
    loop, shift = bool(clip.get('loop')), np.r_[np.asarray(meta.get('root_motion', [0, 0, 0]))[:2], 0]
    hit = set(meta.get('impacts', []))
    worst = {'drift_mm': 0.0, 'res_mm': 0.0, 'seam_mm': 0.0}
    for r in ('toe.L', 'toe.R', 'foot.L', 'foot.R', 'hips', 'chest', 'head', 'hand.L', 'hand.R'):
        P = np.array([mc.xf(D[r], rest.lm[r]) for D in Ds])
        n = len(P) - 1
        d = {'joints': P[:, None], 'loop': loop, 'frames': np.arange(n + 1), 'impacts': sorted(hit),
             'roles': np.array(['x'])}
        res = qm._residual(d)[:, 0] if not loop else np.linalg.norm(P[:n] - sum(sg[k] * np.concatenate(
            [P[n - 3:n] - shift, P[:n], P[:3] + shift])[k:k + n] for k in range(7)), axis=1) * 1000
        worst['res_mm'] = max(worst['res_mm'], float(res.max()))
        worst.setdefault('res_at', {})[r] = int(res.argmax())
        worst['speed_mps'] = max(worst.get('speed_mps', 0.0), float(np.linalg.norm(np.diff(P[:n + 1], axis=0), axis=1).max() * fps))
        idx = np.flatnonzero(meta.get('plants', {}).get(r, [False] * len(P)))
        for run in np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1) if len(idx) else []:
            worst['drift_mm'] = max(worst['drift_mm'], float(np.linalg.norm(P[run, :2] - P[run[0], :2], axis=1).max() * 1000))
        if loop:
            worst['seam_mm'] = max(worst['seam_mm'], float(np.linalg.norm(P[n] - P[0] - shift) * 1000))
    tips = np.array([p['staff_tip'] for p in poses])
    planted = np.asarray(meta.get('plants', {}).get('staff', [False] * len(poses)), bool)
    worst['tip_min_z_mm'] = float(tips[:, 2].min() * 1000)
    worst['tip_planted_z_mm'] = float(np.abs(tips[planted, 2]).max() * 1000) if planted.any() else 0.0
    worst['reach'] = max(mc.leg_ratio(rest, D) for D in Ds)
    if clip['type'] in ('idle', 'walk'):
        free = np.array([mc.xf(D['hand.R'], rest.lm['hand.R']) for D in Ds])
        worst['free_hand_x'], worst['free_hand_z'] = float(np.abs(free[:, 0]).max()), float(free[:, 2].max())
        assert worst['free_hand_x'] <= 0.25 and worst['free_hand_z'] <= 1.05, ('free arm not hanging', clip['id'], worst)
    for sd in mc.SIDES:
        r0 = np.linalg.norm(rest.lm[f'hand.{sd}'] - rest.shoulder[sd])
        over = max(np.linalg.norm(mc.xf(D[f'hand.{sd}'], rest.lm[f'hand.{sd}']) - mc.xf(D['chest'], rest.shoulder[sd])) - r0
                   for D in Ds)
        worst['reach_over_mm'] = max(worst.get('reach_over_mm', -1e9), float(over) * 1000)
    assert worst['reach_over_mm'] <= 1.0, ('hand out of arm reach', clip['id'], worst)
    at = worst.pop('res_at')
    rep[clip['id']] = {k: round(v, 3) for k, v in worst.items()}
    rep[clip['id']]['res_at'] = at
    assert worst['drift_mm'] <= 1.0 and worst['res_mm'] <= 3.0 and worst['seam_mm'] <= 0.5, (clip['id'], worst)
    assert worst['speed_mps'] <= 6.0, ('joint teleports (the cast slam was 11 m/s)', clip['id'], worst)
    assert worst['tip_min_z_mm'] >= -0.01 and worst['tip_planted_z_mm'] <= 0.01 and worst['reach'] <= 0.995, (clip['id'], worst)
    if clip['type'] == 'beats':
        f = meta['impacts'][0]
        assert planted[f] and planted[f:f + 8].all() and abs(tips[f, 2]) < 1e-9, ('slam not on the ground', f)
print('curves', rep)
PY

python3 - "$spec" "$out/v.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s['motion']['clips'] = [c for c in s['motion']['clips'] if c['id'] in ('walk', 'cast')]
s['bake']['mode'] = 'flat'
json.dump(s, open(sys.argv[2], 'w'))
PY
"$here/scripts/char3d" build "$out/v.json" --out "$out" --draft --until motion >/dev/null || fail build
python3 - "$out/build.json" <<'PY' || fail "motion stage metrics"
import json, sys
m = json.load(open(sys.argv[1]))['stages']['motion']
c = m['per_clip']
print('motion', {k: m[k] for k in ('seconds', 'drift_mm_max', 'min_z_mm', 'reach_max')},
      {k: {q: v[q] for q in ('frames', 'updates_per_frame', 'lift_body_mm', 'lift_foot_mm', 'seam_mm')} for k, v in c.items()})
assert m['drift_mm_max'] <= 10 and m['min_z_mm'] >= -5 and m['reach_max'] <= 0.995, m
assert c['walk']['seam_mm'] <= 3 and c['cast']['drift_mm'].get('staff_tip', 99) <= 1, c
assert m['seconds'] <= 40, ('walk + cast motion bake too slow', m['seconds'])
PY
echo "PASS motion"

#!/usr/bin/env bash
# secondary stage: numpy core (springs, loop, cage embedding, smoothing, concave split) and the PC2 driver + Surface
# Deform delivery on a synthetic scene, in headless Blender under heavy.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat > "$T/t.py" <<'EOF'
import math, sys
import numpy as np
sys.path.insert(0, sys.argv[sys.argv.index('--') + 1])
import bpy
from mathutils import Matrix
from mathutils.bvhtree import BVHTree
from c3d.stages import secondary as S

fails = []
def ok(name, cond, info=''):
    print(('PASS ' if cond else 'FAIL ') + name, info)
    if not cond:
        fails.append(name)

rng = np.random.RandomState(1)
n, fps = 72, 30
t = np.arange(n + 1) / fps
ang = np.stack([0.06 * np.sin(2 * np.pi * t / 1.2), 0.03 * np.sin(4 * np.pi * t / 1.2), 0 * t], 1)
rots = np.array([np.array(Matrix.Rotation(np.linalg.norm(a), 3, a / max(np.linalg.norm(a), 1e-9)))
                 if np.linalg.norm(a) > 1e-9 else np.eye(3) for a in ang])
pos = np.stack([0.02 * np.sin(2 * np.pi * t / 1.2), -0.5 * t, 0.02 * np.sin(4 * np.pi * t / 1.2)], 1)
pos += rng.normal(0, 0.0005, pos.shape)
pos[-1] = pos[0] + (0, -0.5 * n / fps, 0)
al, ac = S.frame_accels(rots, pos, fps, True)
al, ac = (S.smooth_series(x, S.FORCE_SIGMA_S * fps, True) for x in (al, ac))
ok('smooth_series loop closes', np.allclose(al[0], al[-1]) and np.allclose(ac[0], ac[-1]))
dirs = np.tile([0.0, 0.3, 1.0], (5, 1)) / math.hypot(0.3, 1.0)
remain = np.cumsum(np.full(5, 0.09)[::-1])[::-1]
out, err = S.spring_chain(al, ac, dirs, np.maximum(remain / 2, S.LEVER_MIN_M), 120, 15, fps, True, 3)
step = np.linalg.norm(np.diff(out, axis=0), axis=2).max()
ok('spring loop exact', err <= 1e-4, f'err={err:.2e}')
ok('spring step <= 0.05 rad on noisy walk forcing', step <= 0.05, f'step={step:.4f}')
ok('spring moves (overlap)', np.linalg.norm(out, axis=2).max() > 0.01)

R, Sg = 12, 24
a = 2 * np.pi * np.arange(Sg) / Sg
G = np.array([[(0.3 + 0.01 * i) * np.cos(a), (0.3 + 0.01 * i) * np.sin(a), np.full(Sg, 1.0 - 0.08 * i)] for i in range(R)])
G = G.transpose(0, 2, 1)
P = np.c_[rng.uniform(-0.35, 0.35, (200, 2)), rng.uniform(0.15, 0.95, 200)]
P[:, :2] *= (0.32 / np.maximum(np.linalg.norm(P[:, :2], axis=1), 1e-6))[:, None] * rng.uniform(0.9, 1.1, (200, 1))
bind = S.embed(P, G, np.zeros(3))
ok('embed/unembed identity', np.abs(S.unembed(bind, G) - P).max() < 1e-9)
Rz = np.array(Matrix.Rotation(0.7, 3, np.array([0.2, 0.3, 1.0]) / np.linalg.norm([0.2, 0.3, 1.0])))
G2 = G @ Rz.T + (0.4, -0.2, 0.1)
ok('embedding follows rigid motion', np.abs(S.unembed(bind, G2) - (P @ Rz.T + (0.4, -0.2, 0.1))).max() < 1e-7)
Gs = S.smooth_grid(G)
rad = np.linalg.norm(Gs[3, :, :2], axis=1)
ok('smooth_grid keeps a lathe round', np.ptp(rad) < 1e-9)

V = np.array([[0, 0, 0], [1, 0, 0], [0.3, 0.3, 0], [0, 1, 0], [2, 0, 0], [3, 0, 0], [3, 1, 0], [2, 1, 0]], float)
faces = S.split_concave(V, [(0, 1, 2, 3), (4, 5, 6, 7)])
ok('split_concave splits only the concave quad', faces[2:] == [(4, 5, 6, 7)] and len(faces) == 3, faces)

A = rng.normal(size=(10, 6, 3))
nxt = A[0] + 0.05
L = S.loop_crossfade(A, nxt)
ok('crossfade wraps with the natural step', np.allclose(A[0] - L[-1], nxt - A[-1]) and np.allclose(L[:2], A[:2]))

cube = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
cf = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
cv = np.array(cube, float)
cf = [f if np.dot(np.cross(cv[f[1]] - cv[f[0]], cv[f[2]] - cv[f[0]]), cv[list(f)].mean(0)) > 0 else f[::-1] for f in cf]
tree = BVHTree.FromPolygons(cube, cf)
body = (tree, np.full(3, -1 - S.REACH_M), np.full(3, 1 + S.REACH_M))
Q = np.array([[0.0, 0.0, 0.98], [0.5, 0.97, 0.0], [3.0, 0.0, 0.0]])
moved = S.push_out(Q, body, 0.004)
ok('push_out clears the body with margin', moved == 2 and abs(Q[0, 2] - 1.004) < 1e-6 and abs(Q[1, 1] - 1.004) < 1e-6
   and S.depth_below(Q, body).max() == 0)

bpy.ops.wm.read_factory_settings(use_empty=True)
arm = bpy.data.objects.new('rig', bpy.data.armatures.new('rig'))
bpy.context.scene.collection.objects.link(arm)
arm.location = (0.5, 0.2, 0)
arm[S.FRAME_PROP] = 0.0
gv = [(x * 0.05, 0.0, 1 - y * 0.05) for y in range(16) for x in range(16)]
gf = [(y * 16 + x, y * 16 + x + 1, (y + 1) * 16 + x + 1, (y + 1) * 16 + x) for y in range(15) for x in range(15)]
me = bpy.data.meshes.new('cloth')
me.from_pydata(gv, [], gf)
ob = bpy.data.objects.new('cloth', me)
bpy.context.scene.collection.objects.link(ob)
ob.parent = arm
bpy.context.view_layer.update()
W = np.array([v.co for v in me.vertices]) @ np.array(ob.matrix_world)[:3, :3].T + np.array(ob.matrix_world)[:3, 3]
X = W - np.array(arm.matrix_world)[:3, 3]
frames = np.array([X + np.c_[np.zeros(len(X)), 0.1 * np.sin(k / 3 + X[:, 0] * 4) * (1 - X[:, 2]), np.zeros(len(X))]
                   for k in range(6)], np.float32)
okb, err = S.drive_part(arm, ob, frames, f'{sys.argv[-1]}/cloth.pc2')
ok('driver binds', okb)
worst = 0.0
for k in range(6):
    arm[S.FRAME_PROP] = float(k)
    arm.update_tag()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    got = np.array([v.co for v in ob.evaluated_get(dg).data.vertices]) @ np.array(ob.matrix_world)[:3, :3].T + np.array(ob.matrix_world)[:3, 3]
    worst = max(worst, np.abs(got - (frames[k] + np.array(arm.matrix_world)[:3, 3])).max())
ok('driver reproduces every cached frame (< 0.5 mm)', worst < 5e-4, f'{worst * 1000:.4f} mm')
ok('Surface Deform sits right after the skin', ob.modifiers[0].type == 'SURFACE_DEFORM')
print('secondary tests:', 'FAIL ' + ', '.join(fails) if fails else 'ok')
sys.exit(1 if fails else 0)
EOF
heavy run --ticket "${CHAR3D_TICKET:-T1032}" -- blender -b --factory-startup -noaudio --python-exit-code 1 \
  --python "$T/t.py" -- "$HERE/scripts" "$T" 2>&1 | grep -E '^(PASS|FAIL|secondary tests|Traceback|  File|[A-Za-z]+Error)'
test "${PIPESTATUS[0]}" -eq 0

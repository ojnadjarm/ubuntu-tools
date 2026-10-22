"""Stage motion: bakes one Action per clip (idle, walk, talk, beats) on ctx.controls, keyed every frame, ground-safe."""
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

from .. import bpyutil as bu
from .. import mocurves as mc

NAME = 'motion'
KOKORO_PY = Path(os.path.expanduser(os.environ.get('CHAR3D_KOKORO_PY', '~/.local/opt/kokoro/bin/python')))
NARRATE = Path(os.path.expanduser('~/.claude/skills/kokoro-narration/render_narration.py'))
TTS_CACHE = Path(os.path.expanduser('~/.cache/char3d/tts'))
G2P = ("import json,sys\nfrom misaki import en\ng=en.G2P(trf=False,british=sys.argv[1]=='b',fallback=None)\n"
       "print(json.dumps([''.join(t.phonemes or '' for t in g(w)[1]) for w in json.loads(sys.argv[2])]))")


class Poser:
    """Sets role world deltas on the rig's control bones and reads back the local basis.

    Each control's parent pose is predicted from its nearest driven ancestor (rigid follow, corrected by the error the
    rig showed on the previous frame), so one depsgraph update poses the whole rig; controls still off target after it
    (constraint-blended parents) are re-set from their evaluated parents, round by round, while their error halves or
    their anchor moved."""
    TOL_M, TOL_R, ROUNDS = 1e-4, 1e-3, 8

    def __init__(self, arm, controls):
        self.arm = arm
        self.W = np.array(arm.matrix_world)
        self.Wi = np.linalg.inv(self.W)
        self.roles = {r: b for r, b in controls.items() if b in arm.pose.bones}
        bones = arm.data.bones
        self.order = sorted(set(self.roles.values()), key=lambda b: len(bones[b].parent_recursive))
        self.rest = {b: np.array(bones[b].matrix_local) for b in self.order}
        self.local = {b: np.linalg.inv(np.array(bones[b].parent.matrix_local)) @ self.rest[b] if bones[b].parent
                      else self.rest[b] for b in self.order}
        self.anchor = {b: self._anchor(arm, b) for b in self.order}
        for b in self.order:
            arm.pose.bones[b].rotation_mode = 'QUATERNION'
        self.reset()
        pbs = arm.pose.bones
        self.par0 = {b: np.array(pbs[b].parent.matrix) if pbs[b].parent else np.eye(4) for b in self.order}
        self.pose0 = {b: np.array(pbs[b].matrix) for b in self.order}
        self.adj = {b: np.eye(4) for b in self.order}
        self.updates = 0

    def _anchor(self, arm, name):
        """Nearest driven bone up the parent chain or through constraint targets on the rig (Rigify parent switches)."""
        seen, todo = {name}, [arm.pose.bones[name].parent]
        while todo:
            pb = todo.pop(0)
            if pb is None or pb.name in seen:
                continue
            if pb.name in self.rest:
                return pb.name
            seen.add(pb.name)
            subs = [t.subtarget for c in pb.constraints if c.type == 'ARMATURE' for t in c.targets if t.target == arm]
            subs += [c.subtarget for c in pb.constraints if getattr(c, 'target', None) == arm and getattr(c, 'subtarget', '')]
            todo += [pb.parent] + [arm.pose.bones[n] for n in subs if n in arm.pose.bones]
        return None

    def reset(self):
        for pb in self.arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()

    def _update(self):
        bpy.context.view_layer.update()
        self.updates += 1

    def apply(self, D):
        pbs = self.arm.pose.bones
        T = {b: self.Wi @ D[r] @ self.W @ self.rest[b] for r, b in self.roles.items() if r in D}
        delta = {b: T[b] @ np.linalg.inv(self.pose0[b]) for b in T}
        pred = {}
        for b in self.order:
            if b in T:
                a = self.anchor[b]
                pred[b] = self.adj[b] @ (delta[a] if a in delta else np.eye(4)) @ self.par0[b]
                basis = np.linalg.inv(self.local[b]) @ np.linalg.inv(pred[b]) @ T[b]
                pbs[b].matrix_basis = Matrix(basis.tolist())
        self._update()
        last, moved = {}, set()
        for _ in range(self.ROUNDS):
            err = {b: self._err(np.array(pbs[b].matrix), T[b]) for b in T}
            bad = [b for b, e in err.items() if (e[0] > self.TOL_M or e[1] > self.TOL_R)
                   and (not last or self.anchor[b] in moved or e[0] < 0.5 * last[b][0] or e[1] < 0.5 * last[b][1])]
            if not bad:
                break
            last, moved = err, set(bad)
            for b in bad:
                pbs[b].matrix = Matrix(T[b].tolist())
            self._update()
        for b in T:
            if pbs[b].parent:
                self.adj[b] = np.array(pbs[b].parent.matrix) @ np.linalg.inv(pred[b]) @ self.adj[b]

    @staticmethod
    def _err(M, T):
        return np.linalg.norm(M[:3, 3] - T[:3, 3]), np.abs(M[:3, :3] - T[:3, :3]).max()

    def basis(self):
        out = {}
        for b in set(self.roles.values()):
            m = self.arm.pose.bones[b].matrix_basis
            out[b] = (np.array(m.to_translation()), np.array(m.to_quaternion()))
        return out


class Ground:
    """Lowest evaluated vertex per region: foot.L/R (body and foot-attached parts near each foot), body (everything else
    low). Only meshes reaching below LOW_H x height are measured; props are excluded (the staff is solved analytically)."""
    LOW_H = 0.3

    def __init__(self, ctx, rest):
        self.rest, self.meshes, self.feet, self.masks = rest, [], [], []
        dg = bpy.context.evaluated_depsgraph_get()
        for p in ctx.parts.values():
            ob = bpy.data.objects.get(p['object'])
            if ob is None or ob.type != 'MESH' or p['stage'] == 'props' or not len(ob.data.vertices):
                continue
            v = bu.world_verts(ob, dg)
            if len(v) and v[:, 2].min() <= self.LOW_H * rest.h:
                self.meshes.append(ob)
                self.feet.append(p['stage'] == 'body' or str(p['attach']).startswith('foot.'))

    def index(self):
        """Region masks on the evaluated meshes as the bake sees them (call after the modifier stack is final)."""
        rest, self.masks = self.rest, []
        dg = bpy.context.evaluated_depsgraph_get()
        for ob, feet in zip(self.meshes, self.feet):
            v = bu.world_verts(ob, dg)
            m = {}
            for s in mc.SIDES:
                pts = np.stack([rest.lm[f'foot.{s}'], rest.ball[s], rest.heel[s]])
                dxy = np.min(np.linalg.norm(v[:, None, :2] - pts[None, :, :2], axis=2), axis=1)
                m[f'foot.{s}'] = np.flatnonzero((dxy < 0.14) & (v[:, 2] < 0.16)) if feet else np.zeros(0, int)
            foot = np.zeros(len(v), bool)
            for idx in m.values():
                foot[idx] = True
            m['body'] = np.flatnonzero(~foot & (v[:, 2] < self.LOW_H * rest.h))
            self.masks.append(m)

    def measure(self):
        dg = bpy.context.evaluated_depsgraph_get()
        low = {'body': 9.0, 'foot.L': 9.0, 'foot.R': 9.0, 'all': 9.0}
        for ob, m in zip(self.meshes, self.masks):
            z = bu.world_verts(ob, dg)[:, 2]
            low['all'] = min(low['all'], float(z.min()))
            for k, idx in m.items():
                if len(idx):
                    low[k] = min(low[k], float(z[idx].min()))
        return low


def _limb(arm, name):
    """Lateral DEF chain above a hand or foot bone: (top joint world head, chain length), None without one."""
    bone, chain = arm.data.bones.get(name or ''), []
    while bone is not None and bone.parent is not None and abs(bone.parent.head_local[0]) > 0.03:
        bone = bone.parent
        chain.append(bone)
    if not chain:
        return None
    return mc.xf(np.array(arm.matrix_world), np.array(chain[-1].head_local)), sum(b.length for b in chain)


def rest_model(ctx, arm):
    """Landmarks, leg and arm chains (lateral DEF bones above each foot and hand), staff geometry from held props."""
    lm = {k: np.asarray(v, float) for k, v in ctx.landmarks.items()}
    legs, shoulders = {}, {}
    for s in mc.SIDES:
        leg = _limb(arm, ctx.bones.get(f'foot.{s}'))
        ank = lm[f'foot.{s}']
        if leg:
            legs[s] = leg
        else:
            hip = np.array([ank[0], lm['hips'][1], lm['hips'][2]])
            legs[s] = (hip, float(np.linalg.norm(hip - ank)))
        limb = _limb(arm, ctx.bones.get(f'hand.{s}'))
        if limb:
            shoulders[s] = limb[0]
    staff = None
    held = [p for p in ctx.parts.values() if p['stage'] == 'props' and str(p['attach']).startswith('hand.')
            and getattr(bpy.data.objects.get(p['object']), 'type', None) == 'MESH']
    if held:
        verts = np.concatenate([bu.world_verts(bpy.data.objects[p['object']]) for p in held])
        tip = verts[verts[:, 2].argmin()].copy()
        if len(verts) > 4000:
            verts = verts[np.linspace(0, len(verts) - 1, 4000).astype(int)]
        pid = next((p['id'] for p in ctx.spec.get('props', []) if p['attach'] == held[0]['attach']), None)
        staff = {'hand': held[0]['attach'], 'tip': tip, 'verts': verts, 'bone': ctx.controls.get(f'prop:{pid}')}
    return mc.Rest(lm, legs, staff, shoulders if len(shoulders) == 2 else None)


def face_keys(ctx):
    """The Key datablock carrying ARKit shape keys (face.shape_key_object, else any part with jawOpen)."""
    name = ctx.face.get('shape_key_object')
    obs = [bpy.data.objects.get(name)] if name else [bpy.data.objects.get(p['object']) for p in ctx.parts.values()]
    for ob in obs:
        if ob is not None and ob.type == 'MESH' and ob.data.shape_keys and 'jawOpen' in ob.data.shape_keys.key_blocks:
            return ob.data.shape_keys
    return None


def drive_map(ctx, arm, rest, keys):
    """role -> control bone the bake sets; jaw/eyes only when the face rig does not own them."""
    roles = ['root', 'torso', 'hips', 'spine', 'chest', 'neck', 'head', 'foot.L', 'foot.R', 'toe.L', 'toe.R',
             'hand.L', 'hand.R']
    aim = ctx.face.get('eye_aim')
    out = {r: ctx.controls[r] for r in roles if ctx.controls.get(r, '') in arm.pose.bones}
    if keys is None and ctx.controls.get('jaw') in arm.pose.bones:
        out['jaw'] = ctx.controls['jaw']
    if isinstance(aim, dict) and aim.get('target') in arm.pose.bones:
        out['eye_target'] = aim['target']
    else:
        out.update({r: ctx.controls[r] for r in ('eye.L', 'eye.R') if ctx.controls.get(r) in arm.pose.bones})
    if rest.staff and rest.staff['bone'] in arm.pose.bones:
        out['prop'] = rest.staff['bone']
    return out


def use_clip(ctx, cid):
    """Assign a clip's Action to the rig and, when it has a face slot, to the face shape keys."""
    clip = ctx.clips[cid]
    act = bpy.data.actions[clip['action']]
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    arm.animation_data.action = act
    keys = face_keys(ctx)
    if keys is not None and clip.get('face_slot'):
        keys.animation_data_create()
        keys.animation_data.action = act
        keys.animation_data.action_slot = act.slots[clip['face_slot']]
    return act


def narrate(ctx, clip):
    """Kokoro (/kokoro-narration) audio + word timings + misaki phonemes, cached by voice, speed and line."""
    macros = ctx.spec['body'].get('macros', {})
    voice = 'bm_george' if macros.get('gender', 1.0) >= 0.5 else 'bf_emma'
    speed = round(0.95 - 0.08 * macros.get('age', 0.5), 2)
    line = clip['line']
    key = hashlib.sha1(f'{voice}|{speed}|{line}'.encode()).hexdigest()[:12]
    cache = TTS_CACHE / key
    cues = cache / 'out' / 'cues.json'
    if not cues.exists() and KOKORO_PY.exists() and NARRATE.exists():
        (cache / 'out').mkdir(parents=True, exist_ok=True)
        unit = {'voice': {'engine': 'kokoro-82M-fp32', 'voice': voice, 'speed': speed},
                'clips': [{'id': clip['id'], 'sentences': re.split(r'(?<=[.!?])\s+', line.strip())}]}
        (cache / 'unit.json').write_text(json.dumps(unit))
        env = dict(os.environ, HF_HUB_OFFLINE='1', NARRATION_KBPS='default')
        subprocess.run([str(KOKORO_PY), '-I', str(NARRATE), str(cache / 'unit.json'), str(cache / 'out')],
                       cwd=cache, env=env, check=True, capture_output=True)
        shutil.rmtree(cache / 'out.raw', ignore_errors=True)
    if not cues.exists():
        words, t = [], 0.15
        for w in re.findall(r"[\w']+", line):
            d = 0.07 * len(w) + 0.08
            words.append({'w': w, 's': t, 'e': t + d, 'ph': w.lower()})
            t += d + (0.3 if re.search(re.escape(w) + r'[.!?,]', line) else 0.05)
        return words, None, voice, speed
    words = json.loads(cues.read_text())['clips'][clip['id']]['words']
    phf = cache / 'phonemes.json'
    if not phf.exists():
        r = subprocess.run([str(KOKORO_PY), '-I', '-c', G2P, voice[0], json.dumps([w['w'] for w in words])],
                           cwd=cache, env=dict(os.environ, HF_HUB_OFFLINE='1'), capture_output=True, text=True, check=True)
        phf.write_text(r.stdout.strip().splitlines()[-1])
    for w, ph in zip(words, json.loads(phf.read_text())):
        w['ph'] = ph
    dst = ctx.out / 'audio'
    dst.mkdir(parents=True, exist_ok=True)
    audio = dst / f'{clip["id"]}.m4a'
    shutil.copyfile(cache / 'out' / 'audio' / f'{clip["id"]}.m4a', audio)
    return words, audio, voice, speed


def _smooth_lift(need, cap, loop):
    """Lift track >= need (where the cap allows), dilated and Gaussian-smoothed so it adds no pops."""
    if not need.any():
        return need
    x = need[:-1] if loop else need
    k = np.exp(-0.5 * (np.arange(-6, 7) / 2.0) ** 2)
    k /= k.sum()
    pad = 6
    xp = np.r_[x[-pad:], x, x[:pad]] if loop else np.r_[np.repeat(x[0], pad), x, np.repeat(x[-1], pad)]
    dil = np.max(np.stack([np.roll(xp, s) for s in range(-3, 4)]), axis=0)
    sm = np.convolve(dil, k, mode='same')[pad:-pad]
    out = np.minimum(np.maximum(sm, x), cap[:-1] if loop else cap)
    return np.r_[out, out[0]] if loop else out


def _runs(mask):
    idx = np.flatnonzero(mask)
    return np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1) if len(idx) else []


def _span(p, mask):
    worst = 0.0
    for run in _runs(np.asarray(mask, bool)):
        if len(run) >= 2:
            q = p[run, :2]
            worst = max(worst, float(np.linalg.norm(q - q[0], axis=1).max()))
    return worst


FINGERS = ('thumb', 'f_index', 'f_middle', 'f_ring', 'f_pinky')
CURL = {'relaxed': (0.22, 0.38, 0.3), 'grip': (1.05, 1.25, 0.85)}


def finger_pose(arm, rest, sign=1.0):
    """Rigify finger FK controls: a relaxed curl on the free hand, a closed grip on the staff hand (thumb at half)."""
    out = {}
    for s in mc.SIDES:
        curl = CURL['grip' if rest.staff and rest.staff['hand'] == f'hand.{s}' else 'relaxed']
        for f in FINGERS:
            for i, a in enumerate(curl):
                b = f'{f}.0{i + 1}.{s}'
                if b in arm.pose.bones:
                    a *= sign * (0.5 if f == 'thumb' else 1.0) * (1.0 + 0.08 * FINGERS.index(f))
                    out[b] = (np.zeros(3), np.array([np.cos(a / 2), np.sin(a / 2), 0.0, 0.0]))
    return out


def bake_clip(ctx, arm, poser, ground, rest, clip, fps, words, keys):
    gen = {'talk': lambda *a: mc.talk(*a, words)}.get(clip['type']) or mc.GENERATORS.get(clip['type'], mc.idle)
    poses, meta = gen(rest, clip, fps, ctx.spec.get('face', {}))
    loop = bool(clip.get('loop', False))
    n = len(poses) - 1
    staff_role = rest.staff['hand'] if rest.staff else None

    def solve(pose):
        if keys is None:
            pose['rot']['jaw'] = mc.rot_x(0.26 * pose['ch'].get('jawOpen', 0.0))
        D = mc.solve(rest, pose)
        y, p = pose['gaze']
        D['eye_target'] = D['head'] @ mc.about(rest.eyes, mc.rot_z(y) @ mc.rot_x(-p))
        if staff_role:
            D.setdefault('prop', D[staff_role])
        return D

    roles = sorted(r for r in ctx.bones if ctx.bones[r] in arm.pose.bones)
    rest_heads = {r: np.array(arm.data.bones[ctx.bones[r]].head_local) for r in roles}
    W = np.array(arm.matrix_world)
    checked = [r for r in roles if r in ('hips', 'chest', 'head', 'foot.L', 'foot.R', 'toe.L', 'toe.R', 'hand.L', 'hand.R')]
    updates0 = poser.updates

    def record(pose):
        """Pose the rig once: basis keys, joint heads, pose error, lowest vertices, reach and staff tip."""
        D = solve(pose)
        poser.apply(D)
        h = {r: bu.bone_world_head(arm, ctx.bones[r]) for r in roles}
        rec = {'basis': poser.basis(), 'heads': [h[r] for r in roles], 'low': ground.measure(),
               'ratio': mc.leg_ratio(rest, D),
               'err': {r: float(np.linalg.norm(h[r] - mc.xf(D[r], mc.xf(W, rest_heads[r])))) for r in checked}}
        if staff_role:
            pb = arm.pose.bones[rest.staff['bone']] if rest.staff['bone'] else arm.pose.bones[ctx.bones[staff_role]]
            rb = arm.data.bones[pb.name].matrix_local
            rec['tip'] = mc.xf(W @ np.array(pb.matrix) @ np.linalg.inv(np.array(rb)) @ np.linalg.inv(W), rest.staff['tip'])
        return rec

    poser.apply(solve(poses[0]))  # warm-up: the previous clip's last pose leaves frame 0 unconverged
    recs = [record(pose) for pose in poses]
    need = {k: np.array([max(0.0, 0.0005 - r['low'][k]) if r['low'][k] < 9 else 0.0 for r in recs])
            for k in ('body', 'foot.L', 'foot.R')}
    cap = np.array([max(0.0, p['lift_cap']) for p in poses])
    lift = {k: _smooth_lift(v, cap if k == 'body' else np.full(n + 1, 1.0), loop) for k, v in need.items()}
    redo = [i for i in range(n + 1) if max(lift[k][i] for k in lift) > 0.0]
    for i in redo:
        pose = poses[i]
        up = mc.mat(t=(0, 0, lift['body'][i]))
        pose['pelvis_t'] = pose['pelvis_t'] + np.array([0, 0, lift['body'][i]])
        for s in mc.SIDES:
            if f'hand.{s}' != staff_role:
                pose['abs'][f'hand.{s}'] = up @ pose['abs'][f'hand.{s}']
            fl = mc.mat(t=(0, 0, lift[f'foot.{s}'][i]))
            pose['abs'][f'foot.{s}'] = fl @ pose['abs'][f'foot.{s}']
            pose['abs'][f'toe.{s}'] = fl @ pose['abs'][f'toe.{s}']
    if redo and staff_role:
        held = [p['abs'][staff_role] for p in poses]
        mc.grip(rest, poses, loop)
        redo = [i for i in range(n + 1) if i in redo or not np.allclose(held[i], poses[i]['abs'][staff_role], atol=1e-6)]
    for i in redo:
        recs[i] = record(poses[i])
    fingers = finger_pose(arm, rest)
    frames = [{**r['basis'], **fingers} for r in recs]
    heads = [r['heads'] for r in recs]
    low_all = [r['low']['all'] for r in recs]
    tips = [r['tip'] for r in recs if 'tip' in r]
    ratio = max(r['ratio'] for r in recs)
    err = {c: max(r['err'][c] for r in recs) for c in checked}
    blink = np.array([max(p['ch'].get('eyeBlinkLeft', 0.0), p['ch'].get('eyeBlinkRight', 0.0)) for p in poses])
    peaks = [i + 1 for i in range(1, n) if blink[i] >= 0.999 and blink[i - 1] < 0.999]
    act, face_slot = write_action(ctx, arm, keys, clip['id'], frames, poses, rest.staff and rest.staff['bone'])
    heads = np.array(heads)
    plants = meta.pop('plants', {})
    drift = {}
    for c in meta['contacts']:
        if c in roles:
            drift[c] = round(_span(heads[:, roles.index(c)], plants.get(c, [True] * (n + 1))) * 1000, 2)
    if tips:
        drift['staff_tip'] = round(_span(np.array(tips), plants.get('staff', [True] * (n + 1))) * 1000, 2)
    rr = heads - heads[:, roles.index('root')][:, None] if 'root' in roles else heads
    info = {'action': act.name, 'start': 1, 'end': n, 'fps': fps, 'loop': loop, 'contacts': meta.pop('contacts'),
            'blinks': peaks, 'face_slot': face_slot,
            'staff_plants': [i + 1 for i, p in enumerate(plants.get('staff', [True] * (n + 1))) if p] if tips else [],
            **{k: v for k, v in meta.items() if k in ('root_motion', 'cycle_s', 'speed_mps', 'beats', 'nods')},
            'impacts': [f + 1 for f in meta.get('impacts', [])]}
    if meta.get('seconds'):
        info['seconds'] = round(meta['seconds'], 3)
    metrics = {'frames': n + 1, 'drift_mm': drift, 'min_z_mm': round(min(low_all) * 1000, 2),
               'reach_max': round(ratio, 3), 'pose_err_mm': {r: round(v * 1000, 1) for r, v in err.items()},
               'seam_mm': round(float(np.linalg.norm(rr[-1] - rr[0], axis=1).max() * 1000), 2) if loop else None,
               'lift_body_mm': round(float(lift['body'].max()) * 1000, 1),
               'lift_foot_mm': round(float(max(lift['foot.L'].max(), lift['foot.R'].max())) * 1000, 1),
               'updates_per_frame': round((poser.updates - updates0) / (n + 1), 2), 'blinks': len(peaks)}
    return info, metrics


def write_action(ctx, arm, keys, name, frames, poses, staff):
    """One Action per clip: rig slot (controls every frame, blink/fx props, staff `hold` off) + face shape-key slot."""
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    fr = np.arange(1, len(frames) + 1, dtype=float)
    rig, face = {}, {}
    for b in frames[0]:
        loc = np.array([k[b][0] for k in frames])
        quat = np.array([k[b][1] for k in frames])
        for i in range(1, len(quat)):
            if quat[i] @ quat[i - 1] < 0:
                quat[i] = -quat[i]
        for i in range(3):
            rig[(f'pose.bones["{b}"].location', i)] = loc[:, i]
        for i in range(4):
            rig[(f'pose.bones["{b}"].rotation_quaternion', i)] = quat[:, i]
    fc = ctx.face.get('controls') or {}
    blink_path = {'eyeBlinkLeft': fc.get('blink.L'), 'eyeBlinkRight': fc.get('blink.R')}
    for c in sorted({c for p in poses for c in p['ch']}):
        vals = np.array([p['ch'].get(c, 0.0) for p in poses])
        if blink_path.get(c):
            rig[(blink_path[c], 0)] = vals
        elif keys is not None and c in keys.key_blocks:
            face[(f'key_blocks["{c}"].value', 0)] = vals
        else:
            arm[c] = 0.0
            rig[(f'["{c}"]', 0)] = vals
    con = arm.pose.bones[staff].constraints.get('hold') if staff in arm.pose.bones else None
    if con:
        con.influence = 0.0
        rig[(f'pose.bones["{staff}"].constraints["hold"].influence', 0)] = np.zeros(len(frames))
    _fcurves(act, arm, rig, fr)
    face_slot = None
    if keys is not None and face:
        keys.animation_data_create()
        keys.animation_data.action = act
        _fcurves(act, keys, face, fr)
        face_slot = keys.animation_data.action_slot.identifier
        keys.animation_data.action = None
    return act, face_slot


def _fcurves(act, owner, series, fr):
    for (path, idx), vals in series.items():
        fc = act.fcurve_ensure_for_datablock(owner, path, index=idx)
        fc.keyframe_points.add(len(vals))
        fc.keyframe_points.foreach_set('co', np.c_[fr, vals].ravel())
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
        fc.update()


def _light_scene(keep):
    """Bake-time scene: only the measured meshes evaluate, without subdivision (its limit surface never dips below the
    cage, so the measured low point is conservative); returns the undo."""
    hidden = [(ob, ob.hide_viewport) for ob in bpy.data.objects if ob.type in ('MESH', 'CURVES') and ob not in keep]
    subsurf = [(m, m.show_viewport) for ob in keep for m in ob.modifiers if m.type == 'SUBSURF']
    for ob, _ in hidden:
        ob.hide_viewport = True
    for m, _ in subsurf:
        m.show_viewport = False
    bpy.context.view_layer.update()

    def restore():
        for ob, v in hidden:
            ob.hide_viewport = v
        for m, v in subsurf:
            m.show_viewport = v
        bpy.context.view_layer.update()
    return restore


def run(ctx):
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    arm.animation_data_create()
    arm.animation_data.action = None
    fps = ctx.spec['motion']['fps']
    bpy.context.scene.render.fps = fps
    keys = face_keys(ctx)
    for pb in arm.pose.bones:
        con = pb.constraints.get('hold')
        if con and pb.name.startswith('prop_'):
            con.influence = 0.0
    rest0 = rest_model(ctx, arm)
    poser = Poser(arm, drive_map(ctx, arm, rest0, keys))
    rest = rest_model(ctx, arm)
    ground = Ground(ctx, rest)
    metrics, tts = {}, None
    restore = _light_scene(ground.meshes)
    ground.index()
    try:
        for clip in ctx.spec['motion']['clips']:
            words = None
            if clip['type'] == 'talk':
                words, audio, voice, speed = narrate(ctx, clip) if clip.get('line') else ([], None, None, None)
                if audio:
                    ctx.files[f'audio:{clip["id"]}'] = str(audio)
                tts = {'voice': voice, 'speed': speed, 'words': len(words), 'audio': bool(audio)}
            info, m = bake_clip(ctx, arm, poser, ground, rest, clip, fps, words, keys)
            ctx.clips[clip['id']] = info
            metrics[clip['id']] = m
    finally:
        restore()
    poser.reset()
    use_clip(ctx, ctx.spec['motion']['clips'][0]['id'])
    worst = max((v for m in metrics.values() for v in m['drift_mm'].values()), default=0.0)
    return {'stub': False, 'clips': len(ctx.clips), 'drift_mm_max': worst,
            'min_z_mm': min(m['min_z_mm'] for m in metrics.values()),
            'reach_max': max(m['reach_max'] for m in metrics.values()), 'tts': tts, 'per_clip': metrics,
            'staff': bool(rest.staff), 'driven': sorted(poser.roles), 'face_keys': keys is not None,
            'legs_m': {s: round(rest.legs[s][1], 3) for s in rest.legs}}

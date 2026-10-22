"""Stage render: one PNG sequence per spec shot (turntable, clip, closeup, expressions grid still) plus image stats."""
import math

import bpy
import numpy as np

from .. import qa_metrics
from .facerig import evaluate, revalidate
from .lookdev import CAMERA, SET, TARGET, apply_rig, rig_for

NAME = 'render'
SENSOR_W = 36.0
CLOSE = ('closeup', 'still')
FACE_HALF_M = 0.12
FACE_DROP_M = 0.06
CLOSE_RISE = 0.02


def subject_top(ctx):
    tops = [max((ob.matrix_world @ v.co).z for v in ob.data.vertices)
            for ob in (bpy.data.objects[p['object']] for p in ctx.parts.values()) if ob.type == 'MESH']
    return max(tops)


def frame_count(ctx, shot):
    fps = ctx.spec['motion']['fps']
    if shot['kind'] == 'still':
        return 1
    if 'frames' in shot:
        return shot['frames']
    if 'seconds' in shot:
        n = max(1, round(shot['seconds'] * fps))
        loop = cycle(ctx, shot)
        return max(1, round(n / loop[0])) * loop[0] if loop else n
    if 'clip' in shot:
        return ctx.clips[shot['clip']]['end']
    return 4 * fps


def eye_objects(ctx):
    return [bpy.data.objects[n] for n in ctx.face.get('eyes', []) if n in bpy.data.objects]


def face_centre(ctx, role):
    """Close shots aim between the eyes and the mouth, so brows, eyes, mouth and beard root fill the frame under the brim."""
    lm = ctx.landmarks
    if role == 'head' and 'eye.L' in lm:
        x, y, z = (np.array(lm['eye.L']) + np.array(lm['eye.R'])) / 2
        return x, y, z - FACE_DROP_M
    return tuple(lm[role])


def place_camera(ctx, shot, n):
    sc = bpy.context.scene
    cam, target = bpy.data.objects[CAMERA], bpy.data.objects[TARGET]
    cam.animation_data_clear()
    close = shot['kind'] in CLOSE
    lens = shot.get('lens_mm', 85 if close else 35)
    cam.data.lens = lens
    aspect = sc.render.resolution_y / sc.render.resolution_x
    half_v = math.atan(SENSOR_W * aspect / 2 / lens)
    if close:
        target.location = face_centre(ctx, shot.get('target', 'head'))
        dist = shot.get('half_m', FACE_HALF_M) / math.tan(half_v)
    else:
        top = subject_top(ctx)
        target.location = (0, 0, top / 2)
        dist = 0.6 * top / math.tan(half_v)
    tx, ty, tz = target.location
    rise = CLOSE_RISE if close else 0.05
    for f in range(1, n + 1):
        a = 2 * math.pi * (f - 1) / n if shot['kind'] == 'turntable' else -0.5
        cam.location = (tx + dist * math.sin(a), ty - dist * math.cos(a), tz + rise * dist)
        if n > 1:
            cam.keyframe_insert('location', frame=f)
    focus(ctx, shot, cam)


def cycle(ctx, shot):
    """Clip shot of a looping clip: (cycle frames, root motion per cycle), so the shot plays the loop for its whole
    length and the camera rides along with the root; None for every other shot."""
    clip = ctx.clips.get(shot.get('clip') or '')
    if shot['kind'] != 'clip' or not clip or not clip.get('loop'):
        return None
    return clip['end'] - clip['start'] + 1, np.array(clip.get('root_motion', (0.0, 0.0, 0.0)), float)


class Follow:
    """Poses output frame i of a cycle() shot: scene frame inside the cycle, rig moved by whole cycles of root motion,
    camera, target, lights and ground (the whole set) carried linearly along the root, so frame i + cycle renders the
    same image as frame i and the shot wraps seamlessly; restore() undoes it."""

    def __init__(self, ctx, shot, n):
        self.ctx, self.n, (self.L, self.rm) = ctx, n, cycle(ctx, shot)
        self.start = ctx.clips[shot['clip']]['start']
        self.arm = bpy.data.objects[ctx.parts['rig']['object']]
        self.cam, self.target = bpy.data.objects[CAMERA], bpy.data.objects[TARGET]
        place_camera(ctx, shot, n)
        bpy.context.scene.frame_set(1)
        self.cam.animation_data_clear()
        self.set = [o for o in set_objects() if o.parent is None and o is not self.arm]
        self.base = [np.array(o.location) for o in [self.arm] + self.set]

    def pose(self, i):
        k, j = divmod(i, self.L)
        bpy.context.scene.frame_set(self.start + j)
        d = self.rm * i / self.L
        for o, b in zip([self.arm] + self.set, self.base):
            o.location = b + (k * self.rm if o is self.arm else d)
        bpy.context.view_layer.update()

    def restore(self):
        for o, b in zip([self.arm] + self.set, self.base):
            o.location = b
        bpy.context.view_layer.update()


def set_objects():
    """Every object of the lookdev set: camera, target, ground and the light rigs."""
    cols = [c for c in bpy.data.collections if c.name == SET or c.name.startswith('char3d_rig_')]
    return list({o for c in cols for o in c.all_objects})


def focus(ctx, shot, cam):
    """DOF on the eye nearest the lens (by the frame-1 camera position), else on the target."""
    cam.data.dof.use_dof = 'fstop' in shot
    if not cam.data.dof.use_dof:
        return
    bpy.context.scene.frame_set(1)
    eyes = eye_objects(ctx)
    near = min(eyes, key=lambda e: (e.matrix_world.translation - cam.location).length) if eyes else None
    cam.data.dof.focus_object = near or bpy.data.objects[TARGET]
    cam.data.dof.aperture_fstop = shot['fstop']


def shot_settings(ctx, shot):
    """Samples tier, light rig and motion blur per shot kind."""
    sc, look = bpy.context.scene, ctx.spec['look']
    tier = 'draft' if ctx.draft else ('closeup' if shot['kind'] in CLOSE else 'final')
    samples = look.get('samples', {}).get(tier, look.get('samples', {}).get('final', 32))
    if look['engine'] == 'CYCLES':
        sc.cycles.samples = samples
    else:
        sc.eevee.taa_render_samples = samples
    rig = rig_for(look, shot['kind'])
    apply_rig(rig)
    sc.render.use_motion_blur = shot['kind'] in ('clip', 'closeup')
    return {'samples': samples, 'rig': rig}


def face_keys_object(ctx):
    """face.shape_key_object, else the first part carrying ARKit keys (the MPFB body ships them)."""
    name = ctx.face.get('shape_key_object')
    obs = [bpy.data.objects[name]] if name else [bpy.data.objects[p['object']] for p in ctx.parts.values()]
    return next((ob for ob in obs if ob.type == 'MESH' and ob.data.shape_keys
                 and 'jawOpen' in ob.data.shape_keys.key_blocks), None)


def set_expression(ctx, weights):
    """ARKit weights through the facerig controls (rig props that drive the keys), undriven keys directly; missing = 0."""
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    controls = ctx.face.get('controls', {})
    ob = face_keys_object(ctx)
    keys = ob.data.shape_keys.key_blocks if ob else []
    for name, path in controls.items():
        arm[path[2:-2]] = weights.get(name, 0.0)
    for kb in list(keys)[1:]:
        if kb.name not in controls:
            kb.value = weights.get(kb.name, 0.0)
    arm.update_tag()
    evaluate()
    return sum(1 for k in weights if k in controls or k in keys)


def render_sequence(ctx, shot, n, frames):
    sc = bpy.context.scene
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    if 'clip' in shot:
        arm.animation_data.action = bpy.data.actions[ctx.clips[shot['clip']]['action']]
    if cycle(ctx, shot):
        fol = Follow(ctx, shot, n)
        for i in range(n):
            fol.pose(i)
            sc.render.filepath = str(frames / f'{i + 1:04d}.png')
            bpy.ops.render.render(write_still=True)
        fol.restore()
        return
    place_camera(ctx, shot, n)
    sc.frame_start, sc.frame_end = 1, n
    sc.render.filepath = str(frames) + '/'
    bpy.ops.render.render(animation=True)


def render_expressions(ctx, shot, frames):
    """One cell per spec expression, tiled into a single full-size grid PNG."""
    sc = bpy.context.scene
    exprs = ctx.spec['face']['expressions']
    names = [shot['expression']] if 'expression' in shot else list(exprs)
    w, h = sc.render.resolution_x, sc.render.resolution_y
    cols = math.ceil(math.sqrt(len(names) * 1.5))
    rows = math.ceil(len(names) / cols)
    cw, ch = w // cols, h // rows
    sc.render.resolution_x, sc.render.resolution_y = cw, ch
    anim = bpy.data.objects[ctx.parts['rig']['object']].animation_data
    action, anim.action = anim.action, None
    place_camera(ctx, shot, 1)
    sc.frame_set(1)
    revalidate()
    grid = np.zeros((rows * ch, cols * cw, 3), np.float32)
    applied, deltas = 0, []
    for i, name in enumerate(names):
        applied += set_expression(ctx, exprs[name])
        cell = frames / f'cell_{name}.png'
        sc.render.filepath = str(cell)
        bpy.ops.render.render(write_still=True)
        r, c = divmod(i, cols)
        px = load_rgb(cell).reshape(ch, cw, 3)
        grid[(rows - 1 - r) * ch:(rows - r) * ch, c * cw:(c + 1) * cw] = px
        deltas += [float(np.abs(px - grid[(rows - 1) * ch:rows * ch, :cw]).mean())] if i else []
        cell.unlink()
    set_expression(ctx, {})
    anim.action = action
    sc.render.resolution_x, sc.render.resolution_y = w, h
    save_rgb(grid, frames / '0001.png')
    return {'cells': len(names), 'grid': [cols, rows], 'keys_set': applied,
            'expr_delta_min': round(min(deltas), 4) if deltas else None}


def load_rgb(path):
    img = bpy.data.images.load(str(path))
    px = np.empty(img.size[0] * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(-1, 4)[:, :3]


def save_rgb(rgb, path):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new('grid', w, h, alpha=False)
    img.pixels.foreach_set(np.concatenate([rgb, np.ones((h, w, 1), np.float32)], 2).ravel())
    img.filepath_raw, img.file_format = str(path), 'PNG'
    img.save()
    bpy.data.images.remove(img)


def run(ctx):
    sc = bpy.context.scene
    wanted = ctx.options.get('shots')
    done = {}
    for shot in ctx.spec['renders']:
        if wanted and shot['id'] not in wanted:
            continue
        n = min(frame_count(ctx, shot), ctx.options.get('max_frames') or 10 ** 6)
        frames = ctx.out / 'frames' / shot['id']
        frames.mkdir(parents=True, exist_ok=True)
        meta = shot_settings(ctx, shot)
        if shot['kind'] == 'still':
            meta.update(render_expressions(ctx, shot, frames))
        else:
            render_sequence(ctx, shot, n, frames)
        pngs = sorted(frames.glob('*.png'))
        stats = [qa_metrics.image_stats(load_rgb(p)) for p in pngs[::max(1, len(pngs) // 8)]]
        ctx.renders[shot['id']] = {'kind': shot['kind'], 'clip': shot.get('clip'), 'frames_dir': str(frames),
                                   'frames': n, 'fps': sc.render.fps,
                                   'size': [sc.render.resolution_x, sc.render.resolution_y], **meta,
                                   'stats': {k: round(float(np.mean([s[k] for s in stats])), 4) for k in stats[0]}}
        done[shot['id']] = n
    return {'shots': done}

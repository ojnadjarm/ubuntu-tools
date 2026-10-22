"""QA judge (numpy + PIL, no bpy): build.json + qa/*.npz -> CHECKS registry -> qa.json and a contact sheet of failing frames."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

LUMA = np.array([0.2126, 0.7152, 0.0722])
SG_WIN = 7
CONTACT_H, CONTACT_V = 0.05, 0.10


def image_stats(rgb):
    """Display-space RGB (N, 3) in 0..1 -> luma stats."""
    luma = rgb @ LUMA
    return {'luma_mean': float(luma.mean()), 'luma_p99': float(np.percentile(luma, 99)),
            'clip_hi_pct': float((rgb.max(1) >= 0.996).mean() * 100)}


def result(cid, value, thr, ok, unit, frames=(), **detail):
    return {'id': cid, 'value': None if value is None else round(float(value), 4), 'threshold': thr, 'unit': unit,
            'pass': bool(ok), 'frames': [int(f) for f in frames][:24], **detail}


def per_frame(cid, series, frames, thr, unit, fail, low=False, **detail):
    """Worst value of a per-frame series (lowest when low) plus the frames where fail(series) holds."""
    series = np.asarray(series, float)
    bad = fail(series)
    worst = int(np.argmin(series) if low else np.argmax(series))
    return result(cid, series[worst], thr, not bad.any(), unit, np.asarray(frames)[bad], frame=int(frames[worst]), **detail)


# ---- motion and mesh checks (per clip npz) -------------------------------------------------------------------------

def foot_slide(build, thr):
    """Max horizontal drift of a contact joint or sole vertex (heel, ball) from its plant start (height < 5 cm over its
    low, speed < 0.1 m/s)."""
    out = []
    for cid, d in _clips(build):
        fr, roles = d['frames'][:-1], list(d['roles'])
        tracks = {str(c): d['joints'][:-1, roles.index(c)] for c in d['contacts']}
        if 'soles' in d and d['soles'].size:
            tracks.update({str(nm): d['soles'][:-1, k] for k, nm in enumerate(d['sole_names'])})
        drift = np.zeros(len(fr))
        worst_joint = None
        for c, p in tracks.items():
            for run in _contact_runs(p, d['fps']):
                dr = np.linalg.norm(p[run, :2] - p[run[0], :2], axis=1) * 100
                if dr.max() > drift.max():
                    worst_joint = c
                drift[run] = np.maximum(drift[run], dr)
        out.append(per_frame(f'plant_drift:{cid}', drift, fr, thr['plant_drift_cm'], 'cm',
                             lambda s: s > thr['plant_drift_cm'], clip=cid, joint=worst_joint))
    return out


def ground_penetration(build, thr):
    out = []
    for cid, d in _clips(build):
        depth = np.maximum(0.0, -d['min_z'][:-1]) * 100
        part = str(d['parts'][d['low_part'][int(depth.argmax())]]) if 'low_part' in d else None
        out.append(per_frame(f'penetration:{cid}', depth, d['frames'][:-1], thr['penetration_cm'], 'cm',
                             lambda s: s > thr['penetration_cm'], clip=cid, part=part))
    return out


def ground_float(build, thr):
    """Lowest vertex above the ground on frames where any contact joint is planted."""
    out = []
    for cid, d in _clips(build):
        P, roles = d['joints'][:-1], list(d['roles'])
        planted = np.zeros(len(P), bool)
        for c in d['contacts']:
            for run in _contact_runs(P[:, roles.index(c)], d['fps']):
                planted[run] = True
        if not planted.any():
            continue
        lift = np.where(planted, np.maximum(0.0, d['min_z'][:-1]), 0.0) * 100
        out.append(per_frame(f'float:{cid}', lift, d['frames'][:-1], thr['float_cm'], 'cm',
                             lambda s: s > thr['float_cm'], clip=cid))
    return out


def self_intersection(build, thr):
    out = []
    for cid, d in _clips(build):
        if 'self_x' not in d or not d['self_x'].size:
            continue
        sx = d['self_x'][:-1]
        part = str(d['self_x_parts'][int(sx.max(0).argmax())])
        out.append(per_frame(f'self_x:{cid}', sx.sum(1), d['frames'][:-1], thr['self_x_pairs'], 'pairs',
                             lambda s: s > thr['self_x_pairs'], clip=cid, part=part, probed=_probed(d)))
    return out


def garment_depth(build, thr):
    """Deepest garment, beard or prop vertex inside the body, mm."""
    out = []
    for cid, d in _clips(build):
        if 'depth' not in d or not d['depth'].size:
            continue
        mm = d['depth'][:-1] * 1000
        part = str(d['depth_parts'][int(mm.max(0).argmax())])
        out.append(per_frame(f'garment_depth:{cid}', mm.max(1), d['frames'][:-1], thr['garment_depth_mm'], 'mm',
                             lambda s: s > thr['garment_depth_mm'], clip=cid, part=part, probed=_probed(d)))
    return out


def jitter(build, thr):
    """Savitzky-Golay(7, cubic) residual per joint; a 1-frame pop of d leaves ~0.67 d. Loop seams belong to loop_seam;
    one-shot clips are judged to their ends and through declared impacts with one-sided fits (_residual)."""
    out = []
    h = SG_WIN // 2
    for cid, d in _clips(build):
        res = _residual(d)
        n = len(res)
        judged = np.ones(n, bool)
        if bool(d['loop']):
            judged[:h] = judged[n - h:] = False
        r = np.where(judged[:, None], res, 0.0)
        worst = r.max(1)
        joint = str(d['roles'][int(r.max(0).argmax())])
        out.append(per_frame(f'jitter:{cid}', worst, d['frames'][:-1], thr['jitter_mm'], 'mm',
                             lambda s: s > thr['jitter_mm'], clip=cid, joint=joint))
    return out


def joint_speed(build, thr):
    """Peak joint speed, m/s (frame-to-frame step x fps, root motion included): a teleport or snap the SG residual
    cannot judge (impact frames, clip edges). Threshold joint_speed_mps, default 6 (a fast staff strike ~4-5)."""
    lim = thr.get('joint_speed_mps', 6.0)
    out = []
    for cid, d in _clips(build):
        J = d['joints'][:-1]
        v = np.r_[np.zeros((1, J.shape[1])), np.linalg.norm(np.diff(J, axis=0), axis=2) * float(d['fps'])]
        joint = str(d['roles'][int(v.max(0).argmax())])
        out.append(per_frame(f'joint_speed:{cid}', v.max(1), d['frames'][:-1], lim, 'm/s', lambda s: s > lim,
                             clip=cid, joint=joint))
    return out


def grip_slip(build, thr):
    """Held prop: hand bone head/tail offset in the prop's frame vs the rest bind, mm (the staff stays in the hand).
    Threshold grip_mm, default jitter_mm (a slip as large as a pop reads as the hand sliding)."""
    lim = thr.get('grip_mm', thr['jitter_mm'])
    out = []
    for cid, d in _clips(build):
        if 'grip' not in d or not d['grip'].size:
            continue
        slip = np.linalg.norm(d['grip'][:-1] - d['grip_rest'][None], axis=2).max(1) * 1000
        out.append(per_frame(f'grip:{cid}', slip, d['frames'][:-1], lim, 'mm', lambda s: s > lim, clip=cid))
    return out


def clip_ends(build, thr):
    """One-shot clips start and end on the idle clip's first pose (root-relative joints), mm, so they chain into idle
    without a pop. Threshold clip_end_mm, default loop_seam_mm (a clip blend is a seam)."""
    lim = thr.get('clip_end_mm', thr['loop_seam_mm'])
    clips = dict(_clips(build))
    base = clips.get('idle')
    out = []
    if base is None:
        return out
    roles = list(base['roles'])
    r = roles.index('root') if 'root' in roles else None
    rel = (lambda J: J - J[r]) if r is not None else (lambda J: J)
    ref = rel(base['joints'][0])
    for cid, d in clips.items():
        if bool(d['loop']) or list(d['roles']) != roles:
            continue
        J = d['joints']
        gaps = np.array([np.linalg.norm(rel(J[i]) - ref, axis=1).max() * 1000 for i in (0, len(J) - 2)])
        worst = int(d['frames'][0] if gaps.argmax() == 0 else d['frames'][-2])
        out.append(result(f'clip_ends:{cid}', gaps.max(), lim, gaps.max() <= lim, 'mm',
                          [worst] if gaps.max() > lim else [], frame=worst, clip=cid, start_mm=round(float(gaps[0]), 2), end_mm=round(float(gaps[1]), 2)))
    return out


def loop_seam(build, thr):
    """Looping clips: SG residual on the wrapped track near the seam, and pose gap last+1 vs first (root motion removed)."""
    out = []
    h = SG_WIN // 2
    for cid, d in _clips(build):
        if not bool(d['loop']):
            continue
        res = _residual(d)
        n = len(res)
        seam = np.r_[0:h, n - h:n]
        J = d['joints']
        gap = np.linalg.norm(J[n] - J[0] - _root_shift(d), axis=1).max() * 1000
        series = np.zeros(n)
        series[seam] = res[seam].max(1)
        series[0] = max(series[0], gap)
        out.append(per_frame(f'loop_seam:{cid}', series, d['frames'][:-1], thr['loop_seam_mm'], 'mm',
                             lambda s: s > thr['loop_seam_mm'], clip=cid, gap_mm=round(float(gap), 3)))
    return out


def staff_contact(build, thr):
    """Held staff on its planted frames (stands, walk plants, the slam and its hold): lowest staff point vs the ground, cm;
    above the ground fails past float_cm (staff_contact_cm), below it past penetration_cm."""
    up, down = thr.get('staff_contact_cm', thr['float_cm']), thr.get('penetration_cm', thr['float_cm'])
    out = []
    for cid, d in _clips(build):
        if 'staff_low' not in d or not len(d.get('staff_plants', [])) or np.isnan(d['staff_low']).all():
            continue
        z = d['staff_low'][:-1] * 100
        plant = np.zeros(len(z), bool)
        idx = np.asarray(d['staff_plants'], int) - int(d['frames'][0])
        plant[idx[(idx >= 0) & (idx < len(z))]] = True
        dev = np.where(plant, np.where(z >= 0, z / up, -z / down), 0.0)
        w = int(np.argmax(dev))
        bad = dev > 1
        out.append(result(f'staff_contact:{cid}', z[w], [-down, up], not bad.any(), 'cm', d['frames'][:-1][bad],
                          frame=int(d['frames'][w]), clip=cid, planted=int(plant.sum()),
                          impacts=[int(f) for f in d.get('impacts', [])]))
    return out


def layer_poke(build, thr):
    """Lower garment layer showing through an upper one (qa_bake.layer_poke on the probed frames), mm."""
    out = []
    for cid, d in _clips(build):
        if 'layer' not in d or not d['layer'].size:
            continue
        mm = d['layer'][:-1] * 1000
        pair = str(d['layer_pairs'][int(mm.max(0).argmax())])
        out.append(per_frame(f'layer_poke:{cid}', mm.max(1), d['frames'][:-1], thr['layer_poke_mm'], 'mm',
                             lambda s: s > thr['layer_poke_mm'], clip=cid, pair=pair, probed=_probed(d)))
    return out


def pair_penetration(build, thr):
    """Penetration depth per collision pair (qa_bake.PEN: beard-robe, robe-body, layer-layer, hat-head, staff-hand) on
    the probed frames, mm, with the per-frame series."""
    out = []
    for cid, d in _clips(build):
        if 'pen' not in d:
            continue
        probed = d['heavy'][:-1]
        frames = d['frames'][:-1]
        for k, pair in enumerate(d['pen_pairs']):
            if not d['pen_probed'][k]:
                continue
            mm = d['pen'][:-1, k] * 1000
            out.append(per_frame(f'pen:{pair}:{cid}', mm, frames, thr['pair_pen_mm'], 'mm',
                                 lambda s: s > thr['pair_pen_mm'], clip=cid, pair=str(pair), probed=int(probed.sum()),
                                 series_mm={int(f): round(float(v), 2) for f, v in zip(frames[probed], mm[probed])}))
    return out


def video_loop(build, thr):
    """Rendered loop shots: mean pixel step from the last frame back to the first vs the median step between neighbouring
    frames (1 = seamless wrap); threshold loop_pop_ratio, default 1.5."""
    lim = thr.get('loop_pop_ratio', 1.5)
    loops = {cid for cid, d in _clips(build) if bool(d['loop'])}
    out = []
    for sid, r in build['renders'].items():
        n = int(r.get('frames', 0))
        if r.get('kind') != 'clip' or r.get('clip') not in loops or n < 4 or not Path(r.get('file', '')).exists():
            continue
        idx = sorted({0, n - 1} | {int(i) for i in np.linspace(0, n - 2, 9)} | {int(i) + 1 for i in np.linspace(0, n - 2, 9)})
        F = dict(zip(idx, read_frames(r['file'], idx, r.get('size'))))
        steps = [np.abs(F[i + 1] - F[i]).mean() for i in idx if i + 1 in F and i + 1 < n]
        wrap = float(np.abs(F[0] - F[n - 1]).mean())
        ratio = wrap / max(float(np.median(steps)), 1e-6)
        out.append(result(f'video_loop:{sid}', ratio, lim, ratio <= lim, 'ratio', [n] if ratio > lim else [], shot=sid,
                          frames_n=n, wrap=round(wrap * 255, 3), step_median=round(float(np.median(steps)) * 255, 3)))
    return out


def lid_visible(build, thr):
    """Eyeball area visible past the lids at each blink peak (declared clip blinks, else inferred minima), %."""
    out = []
    for cid, d in _clips(build):
        if 'lid' not in d or not d['lid'].size:
            continue
        vis = d['lid'][:-1].max(1) * 100
        fr = d['frames'][:-1]
        if np.isnan(vis).all():
            continue
        peaks = [int(np.flatnonzero(fr == f)[0]) for f in d['blinks'] if f in fr] if len(d['blinks']) else _blink_minima(vis)
        if not peaks:
            continue
        s = np.full(len(vis), -1.0)
        s[peaks] = vis[peaks]
        r = per_frame(f'lid_visible:{cid}', s, fr, thr['lid_visible_pct'], '%', lambda x: x > thr['lid_visible_pct'],
                      clip=cid, blinks=[int(fr[p]) for p in peaks])
        out.append(r)
    return out


# ---- shot checks (qa/shots.npz + encoded media) --------------------------------------------------------------------

def framing(build, thr):
    """Min NDC margin of the subject (closeups: the head region) per shot frame."""
    shots = _shots(build)
    out = []
    for sid in _shot_ids(shots, 'framing'):
        m = shots[f'framing:{sid}']
        out.append(per_frame(f'framing:{sid}', m, np.arange(1, len(m) + 1), thr['framing_ndc'], 'ndc',
                             lambda s: s < thr['framing_ndc'], low=True, shot=sid))
    return out


def exposure(build, thr):
    """Subject-masked luma mean in [luma_min, luma_max] and p99 <= luma_p99 (default 0.97) per sampled frame."""
    out = []
    p99_max = thr.get('luma_p99', 0.97)
    for sid, idx, imgs, masks in _shot_images(build):
        st = [_masked_stats(im, m) for im, m in zip(imgs, masks)]
        mean = np.array([s['mean'] for s in st])
        p99 = np.array([s['p99'] for s in st])
        bad = (mean < thr['luma_min']) | (mean > thr['luma_max']) | (p99 > p99_max)
        w = int(np.argmax(np.abs(mean - (thr['luma_min'] + thr['luma_max']) / 2)))
        out.append(result(f'exposure:{sid}', mean.mean(), [thr['luma_min'], thr['luma_max']], not bad.any(), 'luma',
                          idx[bad] + 1, frame=int(idx[w] + 1), shot=sid, p99=round(float(p99.max()), 4)))
    return out


def clipping(build, thr):
    """Subject pixels with a channel >= 0.996 or luma <= 0.004, % (AgX hides overexposure, so exposure pairs with it)."""
    out = []
    for sid, idx, imgs, masks in _shot_images(build):
        st = [_masked_stats(im, m) for im, m in zip(imgs, masks)]
        out.append(per_frame(f'clip:{sid}', [max(s['hi'], s['lo']) for s in st], idx + 1, thr['clip_pct'], '%',
                             lambda x: x > thr['clip_pct'], shot=sid))
    return out


def noise(build, thr):
    """Immerkaer sigma (8-bit units) on subject luma, edge pixels (top 10 % gradient) excluded."""
    out = []
    for sid, idx, imgs, masks in _shot_images(build):
        sig = np.array([noise_sigma(im @ LUMA * 255, _erode(m)) for im, m in zip(imgs, masks)])
        out.append(per_frame(f'noise:{sid}', sig, idx + 1, thr['noise_sigma'], 'sigma8',
                             lambda s: s > thr['noise_sigma'], shot=sid))
    return out


def mp4_size(build, thr):
    return [result(f'mp4_size:{sid}', r['mb'], thr['mp4_mb'], r['mb'] <= thr['mp4_mb'], 'MB', shot=sid)
            for sid, r in build['renders'].items() if r.get('file', '').endswith('.mp4')]


def gltf_valid(build, thr):
    """glTF-Validator on LOD0 and every LOD file; LODs must also keep LOD0's skin joints and morph targets."""
    if not shutil.which('gltf_validator'):
        return []
    lods = build.get('lods', {})
    files = [('gltf', build['files'].get('glb'))] + [(f'gltf_lod{k}', v['file']) for k, v in sorted(lods.items()) if k != '0']
    lim = thr.get('gltf_warnings', thr['gltf_errors'])
    out = []
    for cid, glb in files:
        if not glb or not Path(glb).exists():
            continue
        rep = json.loads(subprocess.run(['gltf_validator', '-o', glb], capture_output=True, text=True).stdout)
        n, w = rep['issues']['numErrors'], rep['issues']['numWarnings']
        ok = n <= thr['gltf_errors'] and w <= lim
        detail = {'errors': n, 'warnings': w}
        if cid != 'gltf' and '0' in lods:
            lod = next(v for k, v in lods.items() if v['file'] == glb)
            kept = {k: lod.get(k) == lods['0'].get(k) for k in ('joints', 'morph_targets')}
            ok = ok and all(kept.values())
            detail.update({k: lod.get(k) for k in kept}, kept=kept)
        out.append(result(cid, n + w, thr['gltf_errors'], ok, 'errors+warnings', **detail))
    return out


def _asset(build):
    path = build['files'].get('qa_asset')
    return json.loads(Path(path).read_text()) if path else None


def lod0_budget(build, thr):
    a = _asset(build)
    if not a:
        return []
    lo, hi = thr.get('lod0_tris_min', 0), thr['lod0_tris_max']
    return [result('lod0_tris', a['lod0_tris'], [lo, hi], lo <= a['lod0_tris'] <= hi, 'tris')]


def skin_influences(build, thr):
    a = _asset(build)
    if not a:
        return []
    shipped = build.get('stages', {}).get('export', {}).get('max_influences', a['max_influences'])
    ok = shipped <= thr['max_influences'] and a['unweighted'] == 0
    return [result('influences', shipped, thr['max_influences'], ok, 'bones', unweighted=a['unweighted'],
                   source=a['max_influences'])]


def lod_ratio(build, thr):
    lods = build.get('lods', {})
    t0 = lods.get('0', {}).get('tris')
    return [result(f'lod{k}_ratio', lods[k]['tris'] / t0, thr[key], lods[k]['tris'] / t0 <= thr[key], 'x LOD0')
            for k, key in (('1', 'lod1_ratio'), ('2', 'lod2_ratio')) if t0 and k in lods and key in thr]


def _worst(a, key, n=5):
    """Top parts by a per-part asset value (non-zero only)."""
    top = sorted(((p[key], pid) for pid, p in a['parts'].items() if p.get(key)), reverse=True)[:n]
    return {pid: v for v, pid in top}


def quads(build, thr):
    """Quad share of authored faces over non-hair parts (tri-weighted) and no n-gons."""
    a = _asset(build)
    if not a:
        return []
    ok = a['quads_pct'] >= thr['quads_pct_min'] and a.get('ngons', 0) == 0
    return [result('quads', a['quads_pct'], thr['quads_pct_min'], ok, '%', ngons=a.get('ngons', 0),
                   ngon_parts=_worst(a, 'ngons'))]


def uv_range(build, thr):
    a = _asset(build)
    if not a:
        return []
    return [result('uv_range', a['uv_outside'], thr['uv_outside'], a['uv_outside'] <= thr['uv_outside'], 'loops',
                   parts=_worst(a, 'uv_outside'))]


def uv_overlap(build, thr):
    """Faces sharing UV space with another face of the same texture set (hair cards and mirrored .R twins exempt)."""
    a = _asset(build)
    if not a or 'uv_overlap' not in a:
        return []
    return [result('uv_overlap', a['uv_overlap'], thr['uv_overlap_faces'], a['uv_overlap'] <= thr['uv_overlap_faces'],
                   'faces', parts=_worst(a, 'uv_overlap'))]


def texel_density(build, thr):
    """Area-weighted px/cm per part at its set's map size: hero sets >= texel_px_cm_hero, the rest >= texel_px_cm_min."""
    a = _asset(build)
    if not a:
        return []
    hero = thr.get('texel_px_cm_hero', thr['texel_px_cm_min'])
    need = {pid: hero if p.get('hero') else thr['texel_px_cm_min'] for pid, p in a['parts'].items()
            if p.get('texel_px_cm') is not None}
    if not need:
        return []
    ratio = {pid: a['parts'][pid]['texel_px_cm'] / n for pid, n in need.items()}
    worst = min(ratio, key=ratio.get)
    low = sorted((pid for pid, r in ratio.items() if r < 1), key=ratio.get)
    return [result('texel_density', a['parts'][worst]['texel_px_cm'], [thr['texel_px_cm_min'], hero], not low, 'px/cm',
                   part=worst, low={pid: a['parts'][pid]['texel_px_cm'] for pid in low[:5]}, below=len(low))]


ALBEDO_RANGE = {'dielectric': (30, 240), 'metal': (170, 250)}
NORMAL_LEN_TOL, NORMAL_LEN_PCT = 0.1, 0.5


def _rgb(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert('RGB'))


def _maps(build, kind):
    a = _asset(build) or {}
    for sid, t in a.get('textures', {}).items():
        f = t['maps'].get(kind, {}).get('file')
        if f and Path(f).exists():
            yield sid, t, f


def _covered(t, shape):
    """Texels inside the set's UV triangles (qa/uv_<set>.npz), flattened; every texel without that file."""
    h, w = shape[:2]
    f = t.get('uv')
    if not f or not Path(f).exists():
        return np.ones(h * w, bool)
    from PIL import Image, ImageDraw
    img = Image.new('1', (w, h), 0)
    draw = ImageDraw.Draw(img)
    for tri in np.load(f)['tris']:
        draw.polygon([(u * w - 0.5, (1 - v) * h - 0.5) for u, v in tri], fill=1)
    return np.asarray(img, bool).reshape(-1)


def albedo_range(build, thr):
    """Covered albedo texels with a channel outside sRGB 30-240 (metal texels by ORM blue > 0.5: 170-250), % per set."""
    pct = {}
    for sid, t, f in _maps(build, 'albedo'):
        img = _rgb(f)
        rgb = img.reshape(-1, 3)
        orm = t['maps'].get('orm', {}).get('file')
        metal = (_rgb(orm)[..., 2].reshape(-1) > 127) if orm and Path(orm).exists() else np.zeros(len(rgb), bool)
        if len(metal) != len(rgb):
            metal = np.zeros(len(rgb), bool)
        cov = _covered(t, img.shape)
        lo = np.where(metal, ALBEDO_RANGE['metal'][0], ALBEDO_RANGE['dielectric'][0])[cov]
        hi = np.where(metal, ALBEDO_RANGE['metal'][1], ALBEDO_RANGE['dielectric'][1])[cov]
        pct[sid] = float(((rgb[cov] < lo[:, None]) | (rgb[cov] > hi[:, None])).any(1).mean() * 100) if cov.any() else 0.0
    if not pct:
        return []
    worst = max(pct, key=pct.get)
    return [result('albedo_range', pct[worst], thr['albedo_out_pct'], pct[worst] <= thr['albedo_out_pct'], '%',
                   set=worst, sets={k: round(v, 3) for k, v in pct.items()})]


def normal_map(build, thr):
    """Covered tangent-space normal texels: mean x/y bias <= normal_bias, |n| off by > 0.1 on <= 0.5 %, no z < 0."""
    rows = {}
    for sid, t, f in _maps(build, 'normal'):
        img = _rgb(f)
        n = img.reshape(-1, 3)[_covered(t, img.shape)].astype(np.float32) / 255 * 2 - 1
        if not len(n):
            continue
        bad = np.abs(np.linalg.norm(n, axis=1) - 1) > NORMAL_LEN_TOL
        rows[sid] = {'bias': float(np.abs(n[:, :2].mean(0)).max()), 'len_off_pct': float(bad.mean() * 100),
                     'z_neg_pct': float((n[:, 2] < 0).mean() * 100)}
    if not rows:
        return []
    fails = [sid for sid, r in rows.items()
             if r['bias'] > thr['normal_bias'] or r['len_off_pct'] > NORMAL_LEN_PCT or r['z_neg_pct'] > 0]
    worst = max(rows, key=lambda k: rows[k]['bias'])
    return [result('normal_map', rows[worst]['bias'], thr['normal_bias'], not fails, 'bias', set=worst, failed=fails,
                   sets={k: {m: round(v, 4) for m, v in r.items()} for k, r in rows.items()})]


COLOURSPACE = {'albedo': 'sRGB', 'emissive': 'sRGB', 'normal': 'Non-Color', 'orm': 'Non-Color'}


def texture_sets(build, thr):
    """Every set has albedo, normal, ORM and emissive files, square power-of-two at texture_px_min..max (draft builds:
    the set's spec size is judged instead of the baked one), in the right colourspace."""
    a = _asset(build)
    if not a or not a.get('textures'):
        return []
    lo, hi = thr.get('texture_px_min', 2048), thr.get('texture_px_max', 4096)
    problems = []
    for sid, t in a['textures'].items():
        size = t['size'] if build.get('draft') else t.get('baked_size') or t['size']
        if not (size and size & (size - 1) == 0 and lo <= size <= hi):
            problems.append(f'{sid}: {size} px')
        if t.get('material') is False:
            problems.append(f'{sid}: no material in the asset loads its maps')
            continue
        for m, want in COLOURSPACE.items():
            mp = t['maps'].get(m, {})
            if not mp.get('file') or not Path(mp['file']).exists():
                problems.append(f'{sid}.{m}: missing')
            elif mp.get('size') and mp['size'][0] != mp['size'][1]:
                problems.append(f'{sid}.{m}: not square {mp["size"]}')
            elif mp.get('colourspace') != want:
                problems.append(f'{sid}.{m}: {mp.get("colourspace")} != {want}')
    return [result('texture_sets', len(problems), 0, not problems, 'problems', sets=len(a['textures']),
                   problems=problems[:10])]


def skeleton(build, thr):
    """Exported game skeleton: unique skin joints <= max_joints (200), one root joint, rig transforms applied, FBX written
    when the spec asks for it."""
    glb = build['files'].get('glb')
    if not glb or not Path(glb).exists():
        return []
    g = _glb_json(glb)
    joints = {j for s in g.get('skins', []) for j in s['joints']}
    parent = {c: i for i, n in enumerate(g.get('nodes', [])) for c in n.get('children', [])}
    roots = sum(1 for j in joints if parent.get(j) not in joints)
    a = _asset(build) or {}
    applied = a.get('skeleton', {}).get('transforms_applied', True)
    want_fbx = build['spec'].get('export', {}).get('fbx')
    fbx = build['files'].get('fbx')
    fbx_ok = not want_fbx or bool(fbx and Path(fbx).exists() and Path(fbx).stat().st_size > 0)
    lim = thr.get('max_joints', 200)
    ok = 0 < len(joints) <= lim and roots == 1 and applied and fbx_ok
    return [result('skeleton', len(joints), lim, ok, 'joints', roots=roots, transforms_applied=applied, fbx=fbx_ok)]


def _glb_json(path):
    import struct
    d = Path(path).read_bytes()
    return json.loads(d[20:20 + struct.unpack('<I', d[12:16])[0]])


CHECKS = [foot_slide, ground_penetration, ground_float, self_intersection, garment_depth, jitter, joint_speed,
          grip_slip, loop_seam, clip_ends, staff_contact, layer_poke, pair_penetration, video_loop, lid_visible, framing, exposure, clipping, noise, mp4_size, gltf_valid, lod0_budget, skin_influences, lod_ratio,
          quads, uv_range, uv_overlap, texel_density, albedo_range, normal_map, texture_sets, skeleton]
NEEDS = {foot_slide: 'plant_drift_cm', ground_penetration: 'penetration_cm', ground_float: 'float_cm',
         self_intersection: 'self_x_pairs', garment_depth: 'garment_depth_mm', jitter: 'jitter_mm',
         joint_speed: 'jitter_mm', grip_slip: 'jitter_mm', loop_seam: 'loop_seam_mm', clip_ends: 'loop_seam_mm',
         staff_contact: 'float_cm', layer_poke: 'layer_poke_mm', pair_penetration: 'pair_pen_mm', video_loop: 'loop_seam_mm', lid_visible: 'lid_visible_pct', framing: 'framing_ndc', exposure: 'luma_min',
         clipping: 'clip_pct', noise: 'noise_sigma', mp4_size: 'mp4_mb', gltf_valid: 'gltf_errors',
         lod0_budget: 'lod0_tris_max', skin_influences: 'max_influences', lod_ratio: 'lod1_ratio',
         quads: 'quads_pct_min', uv_range: 'uv_outside', uv_overlap: 'uv_overlap_faces', texel_density: 'texel_px_cm_min',
         albedo_range: 'albedo_out_pct', normal_map: 'normal_bias', texture_sets: 'texel_px_cm_min',
         skeleton: 'max_influences'}


# ---- helpers -------------------------------------------------------------------------------------------------------

def _clips(build):
    for key, path in build['files'].items():
        if key.startswith('qa:'):
            z = np.load(path)
            d = {k: z[k] for k in z.files}
            n = len(d['joints'])
            d.setdefault('frames', np.arange(n) + int(d.get('start', 1)))
            d.setdefault('blinks', np.array([], int))
            yield key[3:], d


def _probed(d):
    """Frames the full-mesh probes ran on (qa_bake samples them every HEAVY_S); all frames when not recorded."""
    return int(d['heavy'][:-1].sum()) if 'heavy' in d else len(d['joints']) - 1


def _contact_runs(p, fps):
    speed = np.r_[0, np.linalg.norm(np.diff(p[:, :2], axis=0), axis=1) * float(fps)]
    mask = (p[:, 2] < CONTACT_H + p[:, 2].min()) & (speed < CONTACT_V)
    idx = np.flatnonzero(mask)
    runs = np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1) if len(idx) else []
    return [r for r in runs if len(r) >= 3]


def _sg_coeffs(win=SG_WIN, order=3):
    x = np.arange(-(win // 2), win // 2 + 1)
    return np.linalg.pinv(np.vander(x, order + 1, increasing=True))[0]


def _root_shift(d):
    """Horizontal root displacement over one loop (frame n vs 0), so root-motion loops wrap cleanly."""
    roles = list(d['roles'])
    if 'root' not in roles:
        return np.zeros(3)
    r = d['joints'][:, roles.index('root')]
    return np.r_[r[-1, :2] - r[0, :2], 0.0]


def _residual(d):
    """|P - SG(P)| in mm, (n, joints); loops wrap with the root shift, one-shot clips are split at declared impacts
    (a hard stop is a velocity break, not jitter) and fit one-sided at every segment edge."""
    J = d['joints']
    P = J[:-1]
    n, h = len(P), SG_WIN // 2
    cuts = sorted({int(f) - int(d['frames'][0]) for f in d.get('impacts', [])} & set(range(1, n)))
    if bool(d['loop']):
        D = _root_shift(d)
        Q = np.concatenate([P[n - h:] - D, P, P[:h] + D])
        c = _sg_coeffs()
        res = np.linalg.norm(P - sum(c[k] * Q[k:k + n] for k in range(SG_WIN)), axis=2) * 1000
        if not cuts:
            return res
        R = np.zeros(Q.shape[:2])
        for a, b in zip([0] + [x + h for x in cuts], [x + h for x in cuts] + [len(Q)]):
            R[a:b] = sg_segment(Q[a:b])
        return R[h:h + n]
    res = np.zeros(P.shape[:2])
    for a, b in zip([0] + cuts, cuts + [n]):
        res[a:b] = sg_segment(P[a:b])
    return res


def sg_segment(P, win=SG_WIN, order=3):
    """|P - SG(P)| in mm along axis 0, the window shifted inside the segment at its ends (one-sided cubic fits)."""
    m = len(P)
    if m < win:
        return np.zeros(P.shape[:-1])
    V = np.vander(np.arange(win), order + 1, increasing=True)
    H = V @ np.linalg.pinv(V)
    S = np.empty_like(P)
    for j in range(m):
        a = min(max(0, j - win // 2), m - win)
        S[j] = np.tensordot(H[j - a], P[a:a + win], 1)
    return np.linalg.norm(P - S, axis=-1) * 1000


def _blink_minima(vis):
    """Local minima below half the median (open) visibility."""
    open_ = np.median(vis)
    if open_ <= 0:
        return []
    return [i for i in range(1, len(vis) - 1) if vis[i] <= vis[i - 1] and vis[i] < vis[i + 1] and vis[i] < 0.5 * open_]


_SHOTS = {}


def _shots(build):
    path = build['files'].get('qa_shots')
    if not path:
        return {}
    if path not in _SHOTS:
        z = np.load(path)
        _SHOTS[path] = {k: z[k] for k in z.files}
    return _SHOTS[path]


def _shot_ids(shots, prefix):
    return [k.split(':', 1)[1] for k in shots if k.startswith(prefix + ':')]


def _shot_images(build):
    """(shot, frame indices, display RGB 0..1 frames, subject masks) for every rendered shot with media and a mask."""
    shots = _shots(build)
    for sid in _shot_ids(shots, 'mask'):
        r = build['renders'].get(sid, {})
        if not r.get('file') or not Path(r['file']).exists():
            continue
        idx = shots[f'mask_frames:{sid}'].astype(int)
        imgs = read_frames(r['file'], idx, r.get('size'))
        masks = [_resize(m, im.shape[:2]) for m, im in zip(shots[f'mask:{sid}'], imgs)]
        yield sid, idx, imgs, masks


_MEDIA = {}


def read_frames(path, idx, size=None):
    """Frames idx (0-based) of an mp4 (ffmpeg) or a still image (PIL) as float RGB 0..1."""
    key = (path, tuple(int(i) for i in idx))
    if key in _MEDIA:
        return _MEDIA[key]
    if not str(path).endswith('.mp4'):
        from PIL import Image
        frames = [np.asarray(Image.open(path).convert('RGB'), np.float64) / 255] * len(idx)
    else:
        w, h = size
        sel = '+'.join(f'eq(n\\,{int(i)})' for i in idx)
        raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', str(path), '-vf', f"select='{sel}'",
                              '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                             capture_output=True, check=True).stdout
        frames = list(np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3).astype(np.float64) / 255)
    _MEDIA[key] = frames
    return frames


def _resize(mask, shape):
    mh, mw = mask.shape
    return mask[np.arange(shape[0]) * mh // shape[0]][:, np.arange(shape[1]) * mw // shape[1]]


def _erode(m, r=2):
    out = m.copy()
    for _ in range(r):
        out[1:-1, 1:-1] &= out[:-2, 1:-1] & out[2:, 1:-1] & out[1:-1, :-2] & out[1:-1, 2:]
    return out


def _masked_stats(rgb, mask):
    m = mask if mask.any() else np.ones(mask.shape, bool)
    px = rgb[m]
    y = px @ LUMA
    return {'mean': float(y.mean()), 'p99': float(np.percentile(y, 99)),
            'hi': float((px.max(1) >= 0.996).mean() * 100), 'lo': float((y <= 0.004).mean() * 100)}


def noise_sigma(y, mask):
    """Immerkaer (1996) sigma = sqrt(pi/2)/6 * mean|L(y)| over masked, non-edge pixels (Tai & Yang 2008 exclusion)."""
    k = (y[:-2, :-2] - 2 * y[:-2, 1:-1] + y[:-2, 2:] - 2 * y[1:-1, :-2] + 4 * y[1:-1, 1:-1] - 2 * y[1:-1, 2:]
         + y[2:, :-2] - 2 * y[2:, 1:-1] + y[2:, 2:])
    gx = (y[:-2, 2:] + 2 * y[1:-1, 2:] + y[2:, 2:]) - (y[:-2, :-2] + 2 * y[1:-1, :-2] + y[2:, :-2])
    gy = (y[2:, :-2] + 2 * y[2:, 1:-1] + y[2:, 2:]) - (y[:-2, :-2] + 2 * y[:-2, 1:-1] + y[:-2, 2:])
    g = np.abs(gx) + np.abs(gy)
    m = mask[1:-1, 1:-1]
    if not m.any():
        m = np.ones(m.shape, bool)
    m = m & (g <= np.percentile(g[m], 90))
    return float(np.sqrt(np.pi / 2) / 6 * np.abs(k[m]).mean()) if m.any() else 0.0


# ---- contact sheet -------------------------------------------------------------------------------------------------

def contact_sheet(build, checks, path, cols=4, w=384, per_check=3, max_cells=24):
    """JPG grid of failing frames (render frame when one exists, else a front-view joint plot), labelled id/frame/value."""
    from PIL import Image, ImageDraw
    cells = []
    for c in (c for c in checks if not c['pass']):
        frames = c['frames'][:per_check] or [c.get('frame')]
        for f in frames:
            cells.append((f"{c['id']} f{f} {c['value']}{c['unit']}", _cell(build, c, f, w)))
    cells = cells[:max_cells]
    if not cells:
        return None
    h = cells[0][1].height
    rows = -(-len(cells) // cols)
    sheet = Image.new('RGB', (cols * w, rows * (h + 18)), (20, 20, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(cells):
        x, y = i % cols * w, i // cols * (h + 18)
        sheet.paste(im.resize((w, h)), (x, y + 18))
        draw.text((x + 4, y + 3), label, fill=(255, 120, 110))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, quality=85)
    return str(path)


def _cell(build, c, f, w):
    from PIL import Image, ImageDraw
    h = w * 9 // 16
    sid = c.get('shot') or next((s['id'] for s in build['spec'].get('renders', [])
                                 if s.get('clip') == c.get('clip') and s['id'] in build['renders']), None)
    r = build['renders'].get(sid, {}) if sid else {}
    if f is not None and r.get('file') and Path(r['file']).exists() and 1 <= f <= r.get('frames', 0):
        im = read_frames(r['file'], [f - 1], r.get('size'))[0]
        return Image.fromarray((im * 255).astype(np.uint8)).resize((w, h))
    im = Image.new('RGB', (w, h), (36, 36, 44))
    clip = dict(_clips(build)).get(c.get('clip')) if c.get('clip') else None
    if clip is not None and f is not None and f in clip['frames']:
        _draw_joints(ImageDraw.Draw(im), clip, int(np.flatnonzero(clip['frames'] == f)[0]), c.get('joint'), w, h)
    return im


def _draw_joints(draw, d, i, hot, w, h):
    """Front view (x, z) of the baked joints at index i, ground line, the offending joint in red."""
    P, roles = d['joints'], list(d['roles'])
    cx = P[i, :, 0].mean()
    s = (h - 20) / max(1.0, P[:, :, 2].max() + 0.1)
    to = lambda p: (w / 2 + (p[0] - cx) * s, h - 10 - p[2] * s)  # noqa: E731
    draw.line([(0, h - 10), (w, h - 10)], fill=(90, 90, 100))
    for k, role in enumerate(roles):
        x, y = to(P[i, k])
        col = (255, 80, 70) if role == hot else (200, 200, 210)
        draw.ellipse([x - 3, y - 3, x + 3, y + 3], fill=col)
        draw.text((x + 4, y - 6), role, fill=col)


def evaluate(out):
    out = Path(out)
    build = json.loads((out / 'build.json').read_text())
    thr = build['spec']['qa'].get('thresholds', {})
    checks = []
    for check in CHECKS:
        if NEEDS[check] in thr:
            checks += check(build, thr)
    fails = [c['id'] for c in checks if not c['pass']]
    report = {'character': build['spec']['id'], 'checks': checks,
              'summary': {'checks': len(checks), 'pass': len(checks) - len(fails), 'fail': len(fails), 'failed': fails}}
    if fails:
        report['sheet'] = contact_sheet(build, checks, out / 'qa' / 'sheet.jpg')
    (out / 'qa.json').write_text(json.dumps(report, indent=1))
    return report


if __name__ == '__main__':
    rep = evaluate(sys.argv[1])
    s = rep['summary']
    print(f"char3d qa: {s['pass']}/{s['checks']} pass" + (f", FAIL {', '.join(s['failed'])}" if s['fail'] else '')
          + (f" sheet {rep['sheet']}" if rep.get('sheet') else ''))
    sys.exit(1 if s['fail'] else 0)

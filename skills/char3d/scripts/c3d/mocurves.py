"""Motion curves (numpy only): per-frame role poses for idle, walk, talk and beat clips, plus FK over the 15 roles."""
import math

import numpy as np

TAU = 2 * math.pi
TRUNK = [('hips', 'root'), ('spine', 'hips'), ('chest', 'spine'), ('neck', 'chest'), ('head', 'neck'),
         ('jaw', 'head'), ('eye.L', 'head'), ('eye.R', 'head')]
SIDES = {'L': 1.0, 'R': -1.0}
STRIKE = 0.24
PHONE_VISEME = [('pbm', 'PP'), ('fv', 'FF'), ('θð', 'TH'), ('td', 'DD'), ('kgŋ', 'kk'), ('ʃʒʧʤ', 'CH'), ('sz', 'SS'),
                ('nl', 'nn'), ('ɹr', 'RR'), ('w', 'ou'), ('j', 'ih'), ('ɑaʌæɐIW', 'aa'), ('ɛeəɜᵊA', 'E'),
                ('ɪi', 'ih'), ('ɒɔOYo', 'oh'), ('uʊ', 'ou')]
VOWELS = 'ɑaʌæɐIWɛeəɜᵊAɪiɒɔOYouʊ'


# ---------- math ----------

def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler(x=0.0, y=0.0, z=0.0):
    """Radians; + x leans forward (top toward -Y), + z turns the +X side backward."""
    return rot_z(z) @ rot_y(y) @ rot_x(x)


def mat(R=None, t=(0, 0, 0)):
    m = np.eye(4)
    if R is not None:
        m[:3, :3] = R
    m[:3, 3] = t
    return m


def about(pivot, R):
    """4x4 rotation R about a world point."""
    p = np.asarray(pivot, float)
    return mat(R, p - R @ p)


def xf(M, p):
    return M[:3, :3] @ np.asarray(p, float) + M[:3, 3]


def rot_between(a, b):
    """Smallest rotation taking direction a to direction b."""
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), float(a @ b)
    if c > 1 - 1e-12:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def bump(x):
    """0 at both ends with zero slope, 1 at the middle."""
    x = min(max(x, 0.0), 1.0)
    return 16 * x * x * (1 - x) * (1 - x)


def bump3(x):
    """0 at both ends with zero slope and curvature, 1 at the middle (lifts that leave the ground without a kick)."""
    x = min(max(x, 0.0), 1.0)
    return 64 * (x * (1 - x)) ** 3


def glide(x):
    """0 -> 1 with zero end velocity, half smoothstep half minimum-jerk: the lowest 30 fps SG residual for a step."""
    x = min(max(x, 0.0), 1.0)
    return 0.5 * x * x * (3 - 2 * x) + 0.5 * x ** 3 * (10 - 15 * x + 6 * x * x)


def hermite(p0, p1, m0, m1, s):
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * m1


def track(keys, q):
    """Piecewise cubic Hermite through [(q, value, slope)] keys sorted by q; clamps outside."""
    if q <= keys[0][0]:
        return keys[0][1]
    for (q0, v0, s0), (q1, v1, s1) in zip(keys, keys[1:]):
        if q <= q1:
            h = q1 - q0
            return hermite(v0, v1, s0 * h, s1 * h, (q - q0) / h)
    return keys[-1][1]


def smin(a, b, k=0.008):
    """Smooth minimum, never above min(a, b)."""
    m = min(a, b)
    return m - k * math.log(math.exp((m - a) / k) + math.exp((m - b) / k))


# ---------- rest model ----------

class Rest:
    """Rest-pose facts the generators need: landmarks, legs, feet pivots, staff, shoulders and the relaxed arm hang."""
    HANG_DIR, HANG_BEND = (0.1, -0.12, -1.0), 0.96

    def __init__(self, landmarks, legs, staff=None, shoulders=None):
        self.lm = {k: np.asarray(v, float) for k, v in landmarks.items()}
        self.h = self.lm['head'][2] / 0.9
        self.legs = legs
        self.staff = staff
        self.ball, self.heel = {}, {}
        for s in SIDES:
            a, b = self.lm[f'foot.{s}'], self.lm[f'toe.{s}']
            back = (a - b) * np.array([1, 1, 0])
            self.ball[s] = b
            self.heel[s] = np.array([a[0], a[1], 0.0]) + 0.3 * back
        c = self.lm['chest']
        self.shoulder = shoulders or {s: c + np.array([SIDES[s] * 0.1 * self.h, 0, 0.07 * self.h]) for s in SIDES}
        self.hang = {}
        for s in SIDES:
            d = self.lm[f'hand.{s}'] - self.shoulder[s]
            u = np.array(self.HANG_DIR) * [SIDES[s], 1, 1]
            u /= np.linalg.norm(u)
            ax = np.cross(d, u)
            ang = math.atan2(np.linalg.norm(ax), float(d @ u))
            self.hang[s] = (ax / max(np.linalg.norm(ax), 1e-9), ang, (self.HANG_BEND - 1) * np.linalg.norm(d) * u)
        self.eyes = (self.lm['eye.L'] + self.lm['eye.R']) / 2


def blank_pose():
    return {'root_t': np.zeros(3), 'pelvis_t': np.zeros(3), 'rot': {}, 'abs': {}, 'ch': {}, 'gaze': (0.0, 0.0)}


def trunk(rest, pose):
    """FK over the trunk roles: role -> 4x4 world delta from rest."""
    D = {'root': mat(t=pose['root_t'])}
    D['torso'] = D['root'] @ mat(t=pose['pelvis_t'])
    for role, parent in TRUNK:
        base = D[parent] @ mat(t=pose['pelvis_t']) if role == 'hips' else D[parent]
        D[role] = base @ about(rest.lm[role], pose['rot'].get(role, np.eye(3)))
    yaw, pitch = pose['gaze']
    for s in SIDES:
        D[f'eye.{s}'] = D['head'] @ about(rest.lm[f'eye.{s}'], rot_z(yaw) @ rot_x(-pitch))
    return D


def solve(rest, pose):
    """Full role -> 4x4 world delta: trunk FK plus the absolute feet, toes and hands."""
    D = trunk(rest, pose)
    D.update(pose['abs'])
    for s in SIDES:
        D.setdefault(f'foot.{s}', np.eye(4))
        D.setdefault(f'toe.{s}', D[f'foot.{s}'])
        D.setdefault(f'hand.{s}', D['chest'])
    return D


def reach_cap(rest, pose, D_feet, ratio):
    """Largest extra pelvis lift (m) that keeps every leg within ratio x its length."""
    Dh = trunk(rest, pose)['hips']
    cap = 1.0
    for s in SIDES:
        hip, leg = rest.legs[s]
        hj = xf(Dh, hip)
        ank = xf(D_feet[s], rest.lm[f'foot.{s}'])
        d = hj - ank
        r = ratio * leg
        dxy2 = d[0] ** 2 + d[1] ** 2
        cap = min(cap, math.sqrt(max(r * r - dxy2, 0.0)) - d[2])
    return cap


def leg_ratio(rest, D):
    out = 0.0
    for s in SIDES:
        hip, leg = rest.legs[s]
        out = max(out, np.linalg.norm(xf(D['hips'], hip) - xf(D[f'foot.{s}'], rest.lm[f'foot.{s}'])) / leg)
    return out


def staff_hand(rest, tip, p_des):
    """World delta of the staff hand: staff tip at `tip`, staff aimed so the grip lands nearest p_des."""
    st = rest.staff
    g0 = rest.lm[st['hand']] - st['tip']
    R = rot_between(g0, np.asarray(p_des, float) - tip)
    M = mat(t=tip) @ mat(R) @ mat(t=-st['tip'])
    low = (st['verts'] @ M[:3, :3].T + M[:3, 3])[:, 2].min()
    if low < 0.0:
        M[2, 3] -= low
    return M


def rot_axis(axis, a):
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + math.sin(a) * k + (1 - math.cos(a)) * k @ k


def reach(rest, D_chest, side, M, k=0.01):
    """Hand delta pulled toward the shoulder so its wrist stays inside the rest shoulder-to-wrist distance (soft
    limit, k m knee)."""
    sh, w = xf(D_chest, rest.shoulder[side]), xf(M, rest.lm[f'hand.{side}'])
    r = float(np.linalg.norm(rest.lm[f'hand.{side}'] - rest.shoulder[side]))
    d = w - sh
    L = float(np.linalg.norm(d))
    x = (r - L) / k
    lim = r - k * (math.log1p(math.exp(x)) if x < 30 else x)
    return M if L - lim < 1e-6 else mat(t=d * (lim / L - 1)) @ M


def envelope(x, loop, reach=3, sigma=2.0):
    """Smooth track >= x: dilated by `reach` frames, then Gaussian smoothed (no pops where a limit engages)."""
    if not x.any():
        return x
    y = x[:-1] if loop else x
    pad = reach + int(3 * sigma)
    yp = np.r_[y[-pad:], y, y[:pad]] if loop else np.r_[np.repeat(y[0], pad), y, np.repeat(y[-1], pad)]
    dil = np.max(np.stack([np.roll(yp, s) for s in range(-reach, reach + 1)]), axis=0)
    k = np.exp(-0.5 * (np.arange(-int(3 * sigma), int(3 * sigma) + 1) / sigma) ** 2)
    out = np.maximum(np.convolve(dil, k / k.sum(), mode='same')[pad:-pad], y)
    return np.r_[out, out[0]] if loop else out


def grip(rest, poses, loop=False, margin=0.01):
    """Staff hand within arm reach over a whole clip: the staff tilts about its tip toward the shoulder until the grip
    lies within the rest shoulder-to-wrist distance; the per-frame tilt passes through `envelope` so it adds no jitter.
    Reads and writes pose['abs']['prop'] and the staff hand."""
    st = rest.staff
    if not st:
        return poses
    side, hand = st['hand'][-1], st['hand']
    r = float(np.linalg.norm(rest.lm[hand] - rest.shoulder[side])) - margin
    g = float(np.linalg.norm(rest.lm[hand] - st['tip']))
    need, axes = np.zeros(len(poses)), []
    for i, p in enumerate(poses):
        M = p['abs']['prop']
        a = M[:3, :3] @ (rest.lm[hand] - st['tip']) / g
        v = xf(trunk(rest, p)['chest'], rest.shoulder[side]) - xf(M, st['tip'])
        lv = float(np.linalg.norm(v))
        phi = math.acos(min(1.0, max(-1.0, float(a @ v) / lv)))
        theta = math.acos(min(1.0, max(-1.0, (g * g + lv * lv - r * r) / (2 * g * lv))))
        need[i] = max(0.0, phi - theta)
        ax = np.cross(a, v)
        axes.append(ax / max(np.linalg.norm(ax), 1e-12))
    tilt = envelope(need, loop, 4, 3.0)
    for p, t, ax in zip(poses, tilt, axes):
        if t > 0:
            M = p['abs']['prop']
            p['abs']['prop'] = about(xf(M, st['tip']), rot_axis(ax, t)) @ M
        p['abs'][hand] = p['abs']['prop']
    return poses


def free_hand(rest, D_chest, side, th=0.0, off=(0, 0, 0), hang=1.0):
    """Arm lowered from the rest A-pose to a relaxed hang (weight `hang`), swung th rad forward about the shoulder,
    plus a chest-space offset."""
    ax, ang, bend = rest.hang[side]
    H = about(rest.shoulder[side], rot_axis(ax, hang * ang))
    H[:3, 3] += hang * bend
    return D_chest @ mat(t=off) @ about(rest.shoulder[side], rot_x(-th)) @ H


# ---------- face: gaze, blinks, visemes ----------

def gaze_track(rng, seconds, rate, amp_deg=(6.0, 3.0), settle=0.35):
    """Saccade targets [(t, yaw, pitch)] that start and end at centre (loop safe)."""
    t, out = 0.0, [(0.0, 0.0, 0.0)]
    while True:
        t += rng.exponential(1.0 / rate) + 0.12
        if t > seconds - settle:
            break
        if rng.random() < 0.35:
            y, p = 0.0, 0.0
        else:
            y, p = (math.radians(rng.uniform(-a, a)) for a in amp_deg)
        out.append((t, y, p))
    out.append((max(seconds - settle, t - 1.0), 0.0, 0.0))
    return out


def gaze_at(targets, t, dur=0.05):
    y = p = 0.0
    for (t0, y0, p0), (t1, y1, p1) in zip(targets, targets[1:]):
        if t >= t1:
            y, p = y1, p1
        elif t >= t0:
            y, p = y0, p0
    for (t0, y0, p0), (t1, y1, p1) in zip(targets, targets[1:]):
        if t1 <= t < t1 + dur:
            k = smooth((t - t1) / dur)
            return y0 + (y1 - y0) * k, p0 + (p1 - p0) * k
    return y, p


def blink_times(rng, seconds, rate, also=()):
    t, out = 0.25, sorted(also)
    while True:
        t += rng.exponential(1.0 / rate) + 0.6
        if t > seconds - 0.35:
            break
        if all(abs(t - o) > 0.6 for o in out):
            out.append(t)
    return sorted(o for o in out if 0.05 < o < seconds - 0.3)


def blink_at(times, t):
    v = 0.0
    for b in times:
        d = t - b
        if 0 <= d < 0.07:
            v = max(v, smooth(d / 0.07))
        elif 0.07 <= d < 0.11:
            v = 1.0
        elif 0.11 <= d < 0.26:
            v = max(v, 1 - smooth((d - 0.11) / 0.15))
    return v


def phone_viseme(ph):
    for chars, v in PHONE_VISEME:
        if ph in chars:
            return v
    return None


def viseme_events(words):
    """words [{w, s, e, ph}] -> [(t0, t1, viseme)]; vowels get 1.6x the time of consonants."""
    ev = []
    for w in words:
        phones = [c for c in w.get('ph', '') if phone_viseme(c)]
        if not phones:
            continue
        wts = [1.6 if c in VOWELS else 1.0 for c in phones]
        t, k = w['s'], (w['e'] - w['s']) / sum(wts)
        for c, wt in zip(phones, wts):
            ev.append((t, t + wt * k, phone_viseme(c)))
            t += wt * k
    return ev


def channel_tracks(events, presets, seconds, fps, lead=0.03, tau=0.035):
    """Viseme events -> {ARKit channel: per-frame values}, zero-phase smoothed (coarticulation)."""
    hz = 240
    n = int(seconds * hz) + 2
    chans = sorted({c for v in presets.values() for c in v})
    raw = {c: np.zeros(n) for c in chans}
    for t0, t1, v in events:
        for c, w in presets.get(v, {}).items():
            raw[c][int(t0 * hz):int(t1 * hz) + 1] = w
    a = 1 - math.exp(-1.0 / (tau * hz))
    out = {}
    for c, x in raw.items():
        for rev in (False, True):
            y, acc = x[::-1] if rev else x, 0.0
            z = np.empty_like(y)
            for i, v in enumerate(y):
                acc += a * (v - acc)
                z[i] = acc
            x = z[::-1] if rev else z
        ts = np.arange(int(round(seconds * fps)) + 1) / fps + lead
        out[c] = np.interp(ts * hz, np.arange(n), x)
    return out


# ---------- clips ----------

def stand_feet(rest):
    return {s: np.eye(4) for s in SIDES}


def standing(rest, t, seconds, breath_cycles, sway_m, drop_m, pose):
    """Common standing layer: breath, weight shift, soft knees, staff planted at its rest tip."""
    b = math.sin(TAU * breath_cycles * t / seconds)
    w = math.sin(TAU * t / seconds)
    pose['pelvis_t'] = np.array([sway_m * w, 0.0, -drop_m + 0.002 * b])
    pose['rot']['hips'] = euler(y=-0.012 * w, z=0.01 * w)
    pose['rot']['spine'] = euler(x=0.01 - 0.006 * b)
    pose['rot']['chest'] = euler(x=0.02 - 0.012 * b, z=-0.008 * w)
    pose['rot']['neck'] = euler(x=-0.015 + 0.004 * b)
    return b, w


def finish(rest, pose, D_feet, ratio, staff_tip=None, p_off=(0, 0, 0), th_r=0.0, r_off=(0, 0, 0), hl_off=(0, 0, 0),
           hang=1.0):
    """Clamp pelvis height to leg reach, then place hands (staff hand by the tip lock)."""
    cap = reach_cap(rest, pose, D_feet, ratio)
    pose['pelvis_t'][2] = smin(pose['pelvis_t'][2], pose['pelvis_t'][2] + cap)
    pose['lift_cap'] = reach_cap(rest, pose, D_feet, 0.995)
    for s in SIDES:
        pose['abs'][f'foot.{s}'] = D_feet[s]
        pose['abs'].setdefault(f'toe.{s}', D_feet[s])
    D = trunk(rest, pose)
    st = rest.staff
    if st:
        tip = st['tip'] if staff_tip is None else np.asarray(staff_tip, float)
        p_des = xf(D['chest'], rest.lm[st['hand']] + np.asarray(p_off, float))
        pose['abs']['prop'] = pose['abs'][st['hand']] = staff_hand(rest, tip, p_des)
        pose['staff_tip'] = tip
    for s in SIDES:
        role = f'hand.{s}'
        if role not in pose['abs']:
            off = r_off if s == 'R' else hl_off
            M = free_hand(rest, D['chest'], s, th_r if s == 'R' else -th_r, off, hang)
            pose['abs'][role] = reach(rest, D['chest'], s, M)
    return pose


def face_layer(pose, t, rng_state, blinks, gaze, lid_follow=0.5):
    y, p = gaze_at(gaze, t)
    pose['gaze'] = (y, p)
    bl = min(1.0, blink_at(blinks, t) + lid_follow * max(0.0, -p) * 1.5)
    pose['ch']['eyeBlinkLeft'] = pose['ch']['eyeBlinkRight'] = bl


def idle_head(t, secs):
    """Idle head (x, y, z) angles; one-shot clips start and end on idle_head(0, .) so they chain into idle."""
    return -0.01 + 0.015 * math.sin(TAU * 2 * t / secs), 0.0, 0.05 * math.sin(TAU * t / secs + 1.0)


def idle(rest, clip, fps, face, seed=7):
    secs = clip['seconds']
    n = max(2, round(secs * fps))
    rng = np.random.default_rng(seed)
    gz = face.get('gaze', {})
    gaze = gaze_track(rng, secs, 0.5 * gz.get('saccades_per_s', 1.0), (8.0, 3.0))
    blinks = blink_times(rng, secs, gz.get('blinks_per_s', 0.3))
    poses = []
    for f in range(n + 1):
        t = f / fps
        pose = blank_pose()
        b, w = standing(rest, t, secs, max(1, round(secs / 3.6)), 0.012, 0.0, pose)
        pose['rot']['head'] = euler(*idle_head(t, secs))
        face_layer(pose, t, rng, blinks, gaze, gz.get('lid_follow', 0.5))
        poses.append(finish(rest, pose, stand_feet(rest), 0.985, p_off=(0, 0, 0.004 * b), th_r=0.02 * w,
                            r_off=(0, 0, 0.004 * b)))
    return grip(rest, poses, True), {'contacts': ['foot.L', 'foot.R', 'toe.L', 'toe.R']}


def _foot_stance(rest, s, A_k, f, heel, toe_up):
    """Stance foot (f in 0..1): heel-strike roll about the heel, flat, heel rise about the ball (toe stays flat)."""
    off = A_k - rest.lm[f'foot.{s}']
    flat = mat(t=off)
    if f < STRIKE:
        p = -toe_up * (1 - glide(f / STRIKE))
        M = about(rest.heel[s] + off, rot_x(p)) @ flat
        return M, M, p
    if f <= 0.65:
        return flat, flat, 0.0
    p = track([(0.65, 0.0, 0.0), (1.0, heel, heel / 0.35)], f)
    return about(rest.ball[s] + off, rot_x(p)) @ flat, flat, p


def walk(rest, clip, fps, face, seed=11):
    g = clip.get('gait', {})
    secs = clip['seconds']
    T = g.get('cycle_s', 1.2)
    cycles = max(1, round(secs / T))
    T = secs / cycles
    st, heel = g.get('stance', 0.64), g.get('heel_roll', 0.35)
    toe_up, lift = 0.45 * heel, g.get('lift_m', 0.05)
    Dc = 2 * g.get('step_m', 0.3)
    v, a = Dc / T, Dc * st / 2
    n = max(2, round(secs * fps))
    lean = math.radians(g.get('lean_deg', 6))
    rng = np.random.default_rng(seed)
    gz = face.get('gaze', {})
    gaze = gaze_track(rng, secs, 0.3, (4.0, 2.0))
    blinks = blink_times(rng, secs, gz.get('blinks_per_s', 0.3))
    phase = {'L': 0.0, 'R': 0.5}

    def footprint(s, k):
        A = rest.lm[f'foot.{s}'].copy()
        A[1] += -v * (k + phase[s]) * T - a
        return A

    def foot_at(s, t):
        """Stance: planted (the ball counts as planted once it is down). Swing: a pivot sliding from the ball to the
        heel inside the foot travels from the toe-off ball to the next heel strike with zero end velocity, so the ball
        leaves and the heel lands without a velocity jump."""
        u = t / T - phase[s]
        k = math.floor(u)
        q = u - k
        if q < st:
            return _foot_stance(rest, s, footprint(s, k), q / st, heel, toe_up) + (q / st >= STRIKE,)
        fs = (q - st) / (1 - st)
        M0, _, p0 = _foot_stance(rest, s, footprint(s, k), 1.0, heel, toe_up)
        M1, _, p1 = _foot_stance(rest, s, footprint(s, k + 1), 0.0, heel, toe_up)
        ball, hl = rest.ball[s], rest.heel[s]
        a, b = xf(M0, ball), xf(M1, hl)
        pivot = a + (b - a) * glide(fs) + np.array([0, 0, lift * bump3(fs)])
        c = ball + (hl - ball) * smooth(fs)
        p = track([(0.0, p0, heel / 0.35 * (1 - st) / st), (0.55, 0.15 * heel, -1.6 * heel), (1.0, p1, 0.0)], fs)
        M = mat(t=pivot) @ mat(rot_x(p)) @ mat(t=-c)
        flex = -p0 * (1 - smooth(fs / 0.3))
        return M, M @ about(ball, rot_x(flex)), p, False

    st_info = rest.staff
    poses, plants = [], {'toe.L': [], 'toe.R': [], 'staff': []}
    for f in range(n + 1):
        t = f / fps
        ph = (t / T) % 1.0
        pose = blank_pose()
        pose['root_t'] = np.array([0.0, -v * t, 0.0])
        D_feet = {}
        for s in SIDES:
            M, Mt, _, planted = foot_at(s, t)
            D_feet[s] = M
            pose['abs'][f'toe.{s}'] = Mt
            plants[f'toe.{s}'].append(planted)
        c = 0.5 + 0.5 * math.cos(TAU * 2 * (ph - 0.125))
        sway = g.get('sway_m', 0.025) * math.cos(TAU * (ph - 0.3))
        surge = 0.006 * math.sin(TAU * 2 * (ph - 0.125))
        pose['pelvis_t'] = np.array([sway, -surge, -0.02 - g.get('bob_m', 0.018) * c])
        hy = math.radians(g.get('hip_yaw_deg', 6)) * math.cos(TAU * ph)
        sy = math.radians(g.get('shoulder_yaw_deg', 7)) * math.cos(TAU * (ph - 0.03))
        roll = -math.radians(2.0) * math.cos(TAU * (ph - 0.3))
        pose['rot']['hips'] = euler(x=0.25 * lean, y=roll, z=-hy)
        pose['rot']['spine'] = euler(x=0.25 * lean, y=-0.5 * roll, z=0.5 * (sy + hy))
        pose['rot']['chest'] = euler(x=0.5 * lean + 0.01 * c, y=-0.3 * roll, z=0.5 * (sy + hy))
        pose['rot']['neck'] = euler(x=-0.4 * lean, z=-0.4 * sy)
        pose['rot']['head'] = euler(x=-0.5 * lean - 0.012 * c, z=-0.5 * sy)
        face_layer(pose, t, rng, blinks, gaze, gz.get('lid_follow', 0.5))
        tip = None
        if st_info:
            u = t / T - 0.5 - 0.02
            k = math.floor(u)
            q = u - k

            def tip_k(kk):
                p = st_info['tip'].copy()
                p[0] += 0.03 * SIDES[st_info['hand'][-1]]
                p[1] += -v * (kk + 0.52) * T - 0.85 * a
                return p
            if q < st:
                tip = tip_k(k)
                plants['staff'].append(True)
            else:
                fs = (q - st) / (1 - st)
                tip = tip_k(k) + (tip_k(k + 1) - tip_k(k)) * glide(fs) + np.array([0, 0, 0.07 * bump3(fs)])
                plants['staff'].append(False)
        th = g.get('arm_swing', 0.32) * math.cos(TAU * (ph - 0.06))
        poses.append(finish(rest, pose, D_feet, 0.97, staff_tip=tip, th_r=th))
    return grip(rest, poses, True), {'contacts': ['toe.L', 'toe.R'], 'plants': plants, 'root_motion': [0.0, -v * secs, 0.0],
                   'cycle_s': T, 'speed_mps': v}


TALK_EASE_S = 0.5


def talk(rest, clip, fps, face, words, seed=5):
    secs = max(clip['seconds'], (words[-1]['e'] + 0.4) if words else 0.0)
    n = max(2, round(secs * fps))
    rng = np.random.default_rng(seed)
    gz = face.get('gaze', {})
    gaze = gaze_track(rng, secs, gz.get('saccades_per_s', 2.0), (3.5, 2.0))
    pauses = [w['s'] for i, w in enumerate(words) if i and w['s'] - words[i - 1]['e'] > 0.2]
    blinks = blink_times(rng, secs, gz.get('blinks_per_s', 0.4), also=[p - 0.05 for p in pauses])
    vis = channel_tracks(viseme_events(words), face.get('visemes', {}), secs, fps)
    expr = face.get('expressions', {}).get(clip.get('expression', ''), {})
    nods, last = [], -1.0
    for w in words:
        if 'ˈ' in w.get('ph', '') and w['e'] - w['s'] > 0.16 and w['s'] - last > 0.6:
            nods.append(w['s'] - 0.05)
            last = w['s']
    poses = []
    for f in range(n + 1):
        t = f / fps
        pose = blank_pose()
        b, w = standing(rest, t, secs, max(1, round(secs / 3.6)), 0.006, 0.0, pose)
        nod = sum(0.07 * (d / 0.12) * math.exp(1 - d / 0.12) for d in (t - x for x in nods) if d > 0)
        brow = sum(0.35 * math.exp(-((t - x - 0.08) / 0.12) ** 2) for x in nods)
        e = smooth(min(1.0, t / TALK_EASE_S)) * smooth(min(1.0, (secs - t) / TALK_EASE_S))
        h0 = np.array(idle_head(0.0, 1.0))
        hd = h0 + e * (np.array([nod - 0.02, 0.02 * math.sin(TAU * t / secs), 0.04 * math.sin(TAU * t / secs * 0.7)]) - h0)
        pose['rot']['head'] = euler(*hd)
        face_layer(pose, t, rng, blinks, gaze, gz.get('lid_follow', 0.5))
        k = min(f, len(next(iter(vis.values()))) - 1) if vis else 0
        for c in set(vis) | set(expr):
            v = 0.6 * expr.get(c, 0.0) + (vis[c][k] if c in vis else 0.0)
            pose['ch'][c] = min(1.0, max(0.0, v))
        pose['ch']['browInnerUp'] = min(1.0, pose['ch'].get('browInnerUp', 0.0) + brow)
        gest = sum(math.exp(-((t - x - 0.15) / 0.22) ** 2) for x in nods[:2])
        poses.append(finish(rest, pose, stand_feet(rest), 0.985, th_r=0.02 * w + 0.35 * gest,
                            r_off=(0.0, 0.0, 0.004 * b + 0.05 * gest)))
    return grip(rest, poses), {'contacts': ['foot.L', 'foot.R', 'toe.L', 'toe.R'], 'seconds': secs, 'nods': len(nods)}


CAST_SIGMA = {'*': 2.0, 'p_off': 3.0, 'r_off': 3.0, 'th_r': 3.0, 'hang': 3.0}
SLAM_P, SLAM_V_MPS, SLAM_BLEND = 2.0, 5.0, 3
CAST_LEAD = 6


def gauss(values, sigma):
    """Edge-padded Gaussian smoothing of a per-frame track (arrays or scalars), sigma in frames."""
    x = np.array(values, float)
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([np.repeat(x[:1], r, 0), x, np.repeat(x[-1:], r, 0)])
    return sum(k[j] * pad[j:j + len(x)] for j in range(2 * r + 1))


EASE = {'anticipation': smooth, 'raise': lambda x: 1 - (1 - glide(x)) ** 1.6, 'slam': lambda x: x ** SLAM_P,
        'hold': smooth, 'settle': lambda x: smooth(smooth(x))}


def _cast_key(rest, name, beat, base_tip):
    """Pose parameters at the end of a beat (world staff tip, chest-space hand offsets, trunk angles)."""
    h, tip = rest.h, base_tip.copy()
    k = {'pelvis': np.zeros(3), 'spine': 0.0, 'chest': 0.0, 'head': 0.0, 'yaw': 0.0, 'tip': tip,
         'p_off': np.zeros(3), 'r_off': np.zeros(3), 'th_r': 0.0, 'hang': 1.0}
    staff = beat.get('staff')
    if name == 'anticipation':
        k.update(pelvis=np.array([0, 0.01, -beat.get('crouch_m', 0.05)]), spine=0.05, chest=0.1, head=0.06, yaw=0.12)
    elif name == 'raise':
        k.update(pelvis=np.array([0, 0.0, 0.0]), spine=-0.04, chest=-0.1, head=-0.18, yaw=-0.04)
    elif name in ('slam', 'hold'):
        k.update(pelvis=np.array([0, -0.02, -0.04 if name == 'slam' else -0.03]), spine=0.06, chest=0.14,
                 head=0.04, yaw=-0.08)
    if staff == 'back':
        k['tip'] = tip + np.array([0, 0.2, 0.1])
        k['p_off'] = np.array([0, 0.1, -0.03])
    elif staff == 'high':
        k['tip'] = tip + np.array([-0.02, -0.12, 0.3 * h])
        k['p_off'] = np.array([-0.04, -0.1, 0.32 * h])
        k['r_off'] = np.array([-0.08, -0.12, 0.16 * h])
        k['hang'] = 0.0
    elif staff == 'ground' or name == 'hold':
        k['tip'] = tip + np.array([0.02, -0.34, 0.0])
        k['p_off'] = np.array([0, -0.25, 0.05])
        k['r_off'] = np.array([0.05, -0.2, 0.12 * h])
        k['hang'] = 0.0
    return k


def _slam_start(keys, fps):
    """Moves the slam's start key earlier (up to half the beat before) so the staff tip's last step before the impact
    stays under SLAM_V_MPS, and the key before that by half as much so the wind-up keeps its pace; the impact frame is
    kept. Returns the slam start frame, None without a slam."""
    j = next((i for i, (_, nm, _) in enumerate(keys) if nm == 'slam'), None)
    if not j or j < 2:
        return None
    (fp, npv, kp), (fa, na, ka), (fb, _, kb) = keys[j - 2], keys[j - 1], keys[j]
    travel = float(np.linalg.norm(kb['tip'] - ka['tip']))
    need = math.ceil(travel * SLAM_P * fps / SLAM_V_MPS)
    steal = min(max(0, need - (fb - fa)), (fa - fp) // 2)
    keys[j - 1] = (fa - steal, na, ka)
    if j > 2 and steal:
        keys[j - 2] = (fp - steal // 2, npv, kp)
    return fa - steal


def _slam_weight(f, fa, fb):
    """0 -> 1 over SLAM_BLEND frames before the slam start, 1 through the slam: the raw (unsmoothed) tip drives the
    strike so the impact is not a snap from a lagging smoothed tip onto the ground."""
    if fa is None or f > fb:
        return 0.0
    return smooth((f - fa + SLAM_BLEND) / SLAM_BLEND)


def beats(rest, clip, fps, face, seed=3):
    secs = clip['seconds']
    n = max(2, round(secs * fps))
    base_tip = rest.staff['tip'] if rest.staff else np.zeros(3)
    k0 = _cast_key(rest, 'start', {}, base_tip)
    keys = [(0, 'start', k0), (CAST_LEAD, 'lead', k0)]
    f0, glow = CAST_LEAD, [(0, 0.0)]
    for bt in clip.get('beats', []):
        f0 += bt['frames']
        keys.append((f0, bt['name'], _cast_key(rest, bt['name'], bt, base_tip)))
        glow.append((f0, bt.get('glow', glow[-1][1])))
    if keys[-1][1] != 'settle':
        keys.append((min(n, f0 + 12), 'settle', _cast_key(rest, 'settle', {}, base_tip)))
    else:
        keys[-1] = (keys[-1][0], 'settle', _cast_key(rest, 'settle', {}, base_tip))
    slam_f = next((kf for kf, nm, _ in keys if nm == 'slam'), None)
    slam_a = _slam_start(keys, fps)
    rng = np.random.default_rng(seed)
    gz = face.get('gaze', {})
    blinks = blink_times(rng, secs, 0.2)
    gaze = [(0.0, 0.0, 0.0), (secs, 0.0, 0.0)]

    def params(fr):
        if fr <= 0:
            return keys[0][2], None
        for (fa, _, ka), (fb, nm, kb) in zip(keys, keys[1:]):
            if fr <= fb:
                x = EASE.get(nm, smooth)((fr - fa) / max(1, fb - fa))
                out = {c: ka[c] + (kb[c] - ka[c]) * x for c in ka}
                if nm == 'settle':
                    out['tip'] = out['tip'] + np.array([0, 0, 0.05 * bump(x)])
                return out, nm
        return keys[-1][2], None

    raw = [params(f) for f in range(-2, n + 1)]
    names = [nm for _, nm in raw]
    planted = [nm == 'hold' or (nm == 'slam' and f == slam_f) or f == 0 or f >= keys[-1][0]
               for f, nm in zip(range(-2, n + 1), names)]
    track_ = {c: gauss([k[c] for k, _ in raw], CAST_SIGMA.get(c, CAST_SIGMA['*'])) for c in raw[0][0]}
    smoothed = [{c: track_[c][i] for c in track_} for i in range(len(raw))]
    for i, k in enumerate(smoothed):
        w = 1.0 if planted[i] else _slam_weight(i - 2, slam_a, slam_f)
        if w > 0:
            k['tip'] = (1 - w) * k['tip'] + w * raw[i][0]['tip']
    plants = {'staff': []}
    poses = []
    for f in range(n + 1):
        t = f / fps
        k, nm = smoothed[f + 2], names[f + 2]
        kl = smoothed[f]
        pose = blank_pose()
        b, w = standing(rest, t, secs, 1, 0.0, 0.0, pose)
        pose['pelvis_t'] = pose['pelvis_t'] + k['pelvis']
        pose['rot']['hips'] = euler(z=0.4 * k['yaw'])
        hx, _, hz = idle_head(0.0, 1.0)
        pose['rot']['spine'] = euler(x=0.01 - 0.006 * b + k['spine'], z=0.3 * k['yaw'])
        pose['rot']['chest'] = euler(x=0.02 - 0.012 * b + kl['chest'], z=0.3 * kl['yaw'])
        pose['rot']['head'] = euler(x=hx + kl['head'], z=hz)
        face_layer(pose, t, rng, blinks, gaze, gz.get('lid_follow', 0.5))
        gl = np.interp(f, [g[0] for g in glow], [g[1] for g in glow])
        pose['ch']['glow'] = float(gl)
        pose['ch']['burst'] = float(math.exp(-(f - slam_f) / 5.0)) if slam_f is not None and f >= slam_f else 0.0
        plants['staff'].append(planted[f + 2])
        poses.append(finish(rest, pose, stand_feet(rest), 0.985, staff_tip=k['tip'], p_off=k['p_off'],
                            th_r=kl['th_r'], r_off=kl['r_off'], hang=kl['hang']))
    return grip(rest, poses), {'contacts': ['foot.L', 'foot.R', 'toe.L', 'toe.R'], 'plants': plants,
                   'beats': [nm for _, nm, _ in keys[1:]], 'impacts': [slam_f] if slam_f is not None else []}


GENERATORS = {'idle': idle, 'walk': walk, 'beats': beats}

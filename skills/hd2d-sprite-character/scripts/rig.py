"""Shared anatomy helpers: 2-bone IK, walk-cycle feet, lagged secondary motion, Nocturne-AAA-57 ramps."""
import numpy as np
from core import rot_x

TAU = 2 * np.pi

RAMPS = {
    'purple': ['#1d1335', '#2c1b4f', '#41286b', '#5c3889', '#7e52ac', '#a77ad0'],
    'navy': ['#0c1028', '#131a3c', '#1b2550', '#253265', '#32447c'],
    'gold': ['#4f3028', '#6e4a1c', '#b8862e', '#f2c45a', '#fff2b0'],
    'skin': ['#4f3028', '#7a4c34', '#a86a4a', '#d89a74', '#f0d4cc'],
    'skin_young': ['#7a4c34', '#a86a4a', '#d89a74', '#f0d4cc'],
    'beard': ['#32447c', '#5a76ac', '#7894c4', '#9db5da', '#c8dbf0', '#f2f6ff'],
    'silver': ['#131a3c', '#22303a', '#3a4a52', '#7894c4', '#c8dbf0', '#f2f6ff'],
    'steel': ['#0c1028', '#22303a', '#3a4a52', '#5a76ac', '#9db5da', '#c8dbf0', '#f2f6ff'],
    'wood': ['#2e1c22', '#4f3028', '#6a4232', '#7a4c34', '#a86a4a'],
    'leather': ['#2e1c22', '#4f3028', '#6a4232', '#7a4c34', '#a86a4a', '#d89a74'],
    'boot': ['#0c1028', '#2e1c22', '#4f3028', '#6a4232'],
    'crystal': ['#5c3889', '#a77ad0', '#d0a8ee', '#f2f6ff'],
    'hood': ['#15291f', '#24452e', '#3a6a3a', '#6a9a4e', '#94c070'],
    'hood_in': ['#0a1f2c', '#15291f', '#24452e'],
    'linen': ['#4f3028', '#7a4c34', '#a86a4a', '#c49aa8', '#f0d4cc'],
    'legging': ['#0a1f2c', '#15291f', '#24452e', '#3a6a3a'],
    'blonde': ['#6e4a1c', '#b8862e', '#f2c45a', '#fff2b0'],
    'red': ['#2e1c22', '#4c1631', '#8e2240', '#d0404a', '#f08070'],
    'cape_in': ['#2e1c22', '#4c1631', '#8e2240'],
    'strap': ['#2e1c22', '#4f3028', '#6a4232'],
    'dark': ['#06071a', '#0c1028', '#131a3c'],
    'fletch': ['#9db5da', '#c8dbf0', '#f2f6ff'],
}


def mats(**kw):
    out = {}
    for name, spec in kw.items():
        if isinstance(spec, str):
            out[name] = {'ramp': RAMPS[spec]}
        else:
            ramp, extra = spec
            d = {'ramp': RAMPS[ramp]}; d.update(extra); out[name] = d
    return out


def ik(a, c, l1, l2, pole):
    """Middle joint of a 2-bone chain from a to c bending toward pole."""
    a, c, pole = map(lambda v: np.asarray(v, float), (a, c, pole))
    d = c - a; L = np.linalg.norm(d)
    L = min(L, l1 + l2 - 1e-3); u = d / np.linalg.norm(d)
    x = (l1 * l1 - l2 * l2 + L * L) / (2 * L)
    h = np.sqrt(max(l1 * l1 - x * x, 0))
    p = pole - (pole @ u) * u; p /= np.linalg.norm(p) + 1e-9
    return a + u * x + p * h


def smooth(f):
    return f * f * (3 - 2 * f)


def gait(ph, stride, lift, bob_amp, sway=0.6, hip_yaw=0.15, sh_yaw=0.1, arm=0.4, stance=0.6, arm_lag=0.06, heel=0.5):
    """Keyed walk at phase ph: contact (0), down (1/8), passing (1/4), up (3/8), then the other foot.

    feet: [(z, y, pitch) for side -1, +1]; side +1 plants at ph 0, side -1 at ph 0.5. b: pelvis bob (0 = stand,
    lowest at down, highest at up). sway: pelvis x over the stance foot. pyaw/syaw: hip and shoulder counter-rotation
    (radians, + turns the +x side forward). arms: swing angle per side (+ = forward), lagging the shoulders.
    """
    feet = []
    for off in (0.5, 0.0):
        q = (ph + off) % 1.0
        if q < stance:
            f = q / stance
            z, y = stride * (1 - 2 * f), 0.0
            pitch = -0.35 * max(0.0, 1 - f / 0.18) + heel * max(0.0, (f - 0.65) / 0.35) ** 1.5
        else:
            f = (q - stance) / (1 - stance)
            z = stride * (-1 + 2 * smooth(f))
            y = lift * np.sin(np.pi * f ** 0.8)
            pitch = heel * (1 - f) ** 2 - 0.35 * smooth(max(0.0, (f - 0.55) / 0.45))
        feet.append((z, y, pitch))
    c = 0.5 + 0.5 * np.cos(TAU * 2 * (ph - 0.125))
    th = arm * np.cos(TAU * (ph - arm_lag))
    return dict(feet=feet, b=-bob_amp * c, sway=sway * np.cos(TAU * (ph - 0.3)),
                pyaw=hip_yaw * np.cos(TAU * ph), syaw=-sh_yaw * np.cos(TAU * (ph - arm_lag * 0.5)),
                arms=(th, -th), ground=2 * stride / stance, surge=0.35 * np.sin(TAU * 2 * (ph - 0.125)))


def root_path(**kw):
    """Periodic body path ph -> (sway, bob, surge) that drives follow() springs."""
    def r(ph):
        g = gait(ph, **kw); return np.array([g['sway'], g['b'], g['surge']])
    return r


def foot(ft, pitch, ah, coff, toe=3.0, heel=1.4):
    """Ankle point, foot centre and rotation for a foot rolled over its toe (pitch > 0) or heel (pitch < 0)."""
    rise = toe * np.sin(pitch) if pitch > 0 else heel * np.sin(-pitch)
    ank = ft + np.array([0.0, ah + rise, 0.0])
    R = rot_x(pitch)
    return ank, ank + R @ (np.asarray(coff, float) - np.array([0.0, ah, 0.0])), R


def swing_hand(rest, sh, th, bend=0.8):
    """Hand on a pendulum arc about the shoulder: th radians (+ forward); the elbow bends more going forward."""
    rest = np.asarray(rest, float); L = np.linalg.norm(rest - sh)
    fwd = max(th, 0.0) * bend
    return rest + np.array([0.0, L * (1 - np.cos(th)) + fwd * 1.2, L * np.sin(th) + fwd * 1.5])


def yaw(off, a):
    """Rotate a local offset about y; + moves the +x side toward +z (forward)."""
    c, s = np.cos(a), np.sin(a)
    return np.array([off[0] * c - off[2] * s, off[1], off[0] * s + off[2] * c])


def follow(root, f0, zeta, ph, cycles=4, steps=192):
    """Steady-state offset of a spring-damper tip trailing a periodic root(ph)->xyz: lag, overshoot, settle.

    f0 = natural frequency in oscillations per walk cycle (low = heavy cloth), zeta = damping ratio (< 1 overshoots).
    """
    w = TAU * f0; dt = 1.0 / steps
    a = np.asarray(root(0.0), float); x = a.copy(); v = np.zeros(3)
    n = cycles * steps; target = int(round((ph % 1.0) * steps)) + (cycles - 1) * steps
    prev = a
    for i in range(1, n + 1):
        a = np.asarray(root((i * dt) % 1.0), float)
        av = (a - prev) / dt; prev = a
        acc = -w * w * (x - a) - 2 * zeta * w * (v - av)
        v = v + acc * dt; x = x + v * dt
        if i == target:
            return x - a
    return x - a


def lag(ph, amt, delay, harm=1):
    """Secondary motion that trails the driver by `delay` of a cycle."""
    return amt * np.sin(TAU * harm * (ph - delay))

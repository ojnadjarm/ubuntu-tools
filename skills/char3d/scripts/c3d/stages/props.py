"""Stage props: held items built by code, one object per spec part (staff: shaft, ferrule, binding, knob, claws,
crystal) plus a crystal light."""
import math

import bmesh
import bpy
import numpy as np

from .. import bpyutil as bu
from .. import envelope

NAME = 'props'
CLEAR_GARMENT = 0.05
CRYSTAL_F = (0.0, 0.1, 0.62, 0.7, 1.0)
CRYSTAL_R = (0.0, 0.25, 0.27, 0.24, 0.0)
CRYSTAL_SKEW = (0.0, 0.07, -0.05, 0.08, -0.06, 0.04)
BIND_ANGLE = math.radians(5.5)
CLAW_A0 = -math.pi / 6  # world angle of the first claw and its facet centre; front (-y) sits between two claws
TENDRIL_TWIST = 0.6
SATELLITES = ((0.42, 0.55, 0.62), (0.34, 0.6, 0.5), (0.3, 0.5, 0.75))  # height x crystal, tilt rad, root x knob r
HAND_REACH = 0.3
PALM = (0.02, 0.09)


def sweep(centers, radii, ring=16, cap=(True, True)):
    """Verts and quad faces of a ring swept along centers (k, 3); radii (k,) or (k, ring); a cap closes an end."""
    k = len(centers)
    radii = np.broadcast_to(np.asarray(radii, float).reshape(k, -1), (k, ring))
    tan = np.gradient(centers, axis=0)
    tan /= np.linalg.norm(tan, axis=1, keepdims=True)
    n = np.cross(tan[0], [1.0, 0, 0] if abs(tan[0][0]) < 0.9 else [0, 1.0, 0])
    a = 2 * np.pi * np.arange(ring) / ring
    verts = []
    for i in range(k):
        n = n - n.dot(tan[i]) * tan[i]
        n /= np.linalg.norm(n)
        b = np.cross(tan[i], n)
        verts += list(centers[i] + radii[i][:, None] * (np.cos(a)[:, None] * n + np.sin(a)[:, None] * b))
    return verts, loft_faces(k, ring) + caps(verts, centers, k, ring, cap)


def loft_faces(k, ring, start=0):
    return [(start + i * ring + s, start + i * ring + (s + 1) % ring, start + (i + 1) * ring + (s + 1) % ring,
             start + (i + 1) * ring + s) for i in range(k - 1) for s in range(ring)]


def caps(verts, centers, k, ring, cap):
    """Triangle fans closing the first and/or last ring; appends the centre vertices to verts."""
    faces = []
    for end, i, flip in ((0, 0, True), (1, k - 1, False)):
        if cap[end]:
            verts.append(centers[i])
            c = len(verts) - 1
            faces += [((i * ring + (s + 1) % ring, i * ring + s, c) if flip else (i * ring + s, i * ring + (s + 1) % ring, c))
                      for s in range(ring)]
    return faces


def merge(name, pieces, smooth=True):
    """One mesh object from several (verts, faces) pieces."""
    verts, faces = [], []
    for v, f in pieces:
        faces += [tuple(len(verts) + i for i in face) for face in f]
        verts += list(v)
    ob = bu.mesh_object(name, verts, faces)
    ob.data.polygons.foreach_set('use_smooth', [smooth] * len(ob.data.polygons))
    return ob


def tube(name, centers, radii, ring=16, cap=(True, True)):
    return merge(name, [sweep(centers, radii, ring, cap)])


def bump(t, at, width):
    return np.exp(-((t - at) / width) ** 2)


def palm_grip(ob, wrist, chest, r):
    """Vertical shaft axis of radius r that touches the open palm: the palm centre (hand verts PALM metres past the
    wrist) moved palmar (the hand's thin axis, facing the body midline), then the nearest axis no body vertex enters.
    Returns the grip point at palm height and the gap to the skin."""
    co = bu.world_verts(ob)
    w = np.asarray(wrist, float)
    out = w - np.asarray(chest, float)
    out /= np.linalg.norm(out)
    rel = co - w
    near = co[np.linalg.norm(rel, axis=1) < HAND_REACH]
    hand = co[(rel @ out > 0.005) & (np.linalg.norm(rel, axis=1) < 0.22)]
    if len(hand) < 50:
        return None, None
    c = hand.mean(0)
    vt = np.linalg.svd(hand - c, full_matrices=False)[2]
    a0 = vt[0] * np.sign(vt[0] @ (c - w))
    n = vt[2] * -np.sign(vt[2][:2] @ w[:2])
    along = (hand - w) @ a0
    pc = hand[(along > PALM[0]) & (along < PALM[1])].mean(0)
    target = (pc + n * (r + 0.012))[:2]
    g = np.linspace(-0.07, 0.07, 71)
    cand = target + np.stack(np.meshgrid(g, g), -1).reshape(-1, 2)
    gap = np.linalg.norm(near[None, :, :2] - cand[:, None], axis=2).min(1) - r
    i = int(np.argmin(np.where(gap >= 0, np.linalg.norm(cand - target, axis=1), np.inf)))
    return np.array([cand[i, 0], cand[i, 1], pc[2]]), float(gap[i])


class Staff:
    """Vertical staff on the ground beside the hand, outside every garment: a gnarled shaft in a silver ferrule, a
    leather-wrapped grip, a carved knob whose claws grip one faceted crystal; top parts coaxial."""

    def __init__(self, spec, prop, hand, rng, grip=None):
        self.parts = {p['kind']: p for p in prop['parts']}
        self.L = prop.get('length_m', 1.75)
        self.rng = rng
        self.hc = self.parts.get('crystal', {}).get('size_m', 0.1)
        self.kr = self.parts.get('knob', {}).get('size_m', 0.032)
        self.r = self.parts.get('shaft', {}).get('size_m', 0.026)
        self.z_k1 = self.L - self.hc + 0.012
        self.z_k0 = self.z_k1 - 2.4 * self.kr
        self.z_top = self.z_k0 + 0.3 * (self.z_k1 - self.z_k0)
        at = hand if grip is None else grip
        hx, hy = at[0], at[1]
        need = envelope.radius(spec, np.linspace(0, self.L, 200)).max() + CLEAR_GARMENT
        rho = math.hypot(hx, hy)
        scale = max(rho, need) / max(rho, 1e-6)
        self.side = np.array([-hy, hx, 0.0]) / max(rho, 1e-6)
        self.grip_z = prop.get('grip', 0.58) * self.L if grip is None else float(grip[2])
        self.base = np.zeros(3)
        self.base = np.array([hx * scale, hy * scale, 0.0]) - (self.axis(self.grip_z) - [0, 0, self.grip_z])
        self.grip = self.axis(self.grip_z)
        bw = self.parts.get('binding', {}).get('size_m', 0.03)
        self.bind = (self.grip_z - 4.3 * bw, self.grip_z + 3.7 * bw) if 'binding' in self.parts else (0, 0)
        self.fh = 3.1 * self.parts['ferrule'].get('size_m', 0.03) if 'ferrule' in self.parts else 0.0
        zs = rng.uniform(0.2, 0.9, 12) * self.L
        free = (np.abs(zs - np.mean(self.bind)) > (self.bind[1] - self.bind[0]) / 2 + 0.05) & (zs > self.fh + 0.06)
        self.knots = zs[free][:4]

    def axis(self, z):
        """Centre line at height z: a slight bow and wobble in the shaft, straight through the head."""
        zz = np.atleast_1d(np.asarray(z, float))
        bend = np.sin(np.pi * np.clip(zz / self.z_k0, 0, 1))
        pts = self.base + ((0.012 + 0.003 * np.sin(7 * zz + 1.3)) * bend)[:, None] * self.side
        pts[:, 2] = zz
        return pts if np.ndim(z) else pts[0]

    def shaft_r(self, z):
        """Mean shaft radius at z: tapering up, swelling at knots, thinning into the ferrule foot."""
        z = np.asarray(z, float)
        knots = sum((0.16 * bump(z, zn, 0.025) for zn in self.knots), np.zeros_like(z))
        foot = 1 - 0.12 * bump(z, 0, 0.03)
        return self.r * (0.84 + 0.16 * z / self.z_top) * foot * (1 + knots)

    def shaft(self, name, part):
        z = np.linspace(0.5 * self.fh, self.z_top, 32)
        a = 2 * np.pi * np.arange(16) / 16
        rr = self.shaft_r(z)[:, None] * (1 + 0.05 * np.sin(3 * a[None] + 5 * z[:, None])
                                         + 0.03 * np.sin(7 * a[None] - 11 * z[:, None]))
        return tube(name, self.axis(z), rr, 16, (True, False))

    def ferrule(self, name, part):
        """Silver foot cap: a blunt cone foot, a raised band, a plain sleeve, a second band and a lip onto the wood;
        doubled rows keep the band edges crisp."""
        R = part.get('size_m', 0.03)
        zr = [0.0, 0.12, 0.45, 0.8, 0.82, 0.86, 1.08, 1.12, 1.15, 2.2, 2.23, 2.26, 2.46, 2.5, 2.53, 2.88, 2.91, 2.95,
              3.06, 3.1]
        rr = [0.32, 0.55, 0.76, 0.86, 0.95, 1.0, 1.0, 0.95, 0.9, 0.88, 0.94, 0.98, 0.98, 0.94, 0.9, 0.88, 0.96, 1.02,
              1.02, 0.0]
        z = np.array(zr) * R
        r = np.array(rr) * R
        r[-1] = 1.02 * float(self.shaft_r(z[-1]))
        return tube(name, self.axis(z), r, 20, (True, False))

    def binding(self, name, part):
        """Leather strap wound bottom to top in narrow turns, each turn's thick rounded lower edge lapping the thin
        upper edge of the last, ends trimmed flat to the grip, cord ties at both ends and a loose tail off the top."""
        th = 0.0026
        z0, z1 = self.bind
        r0 = 1.06 * float(self.shaft_r(0.5 * (z0 + z1)))
        pitch = 2 * np.pi * r0 * math.tan(BIND_ANGLE)
        hv = 1.2 * pitch
        turns = (z1 - z0 - hv) / pitch + 2
        n = int(turns * 12) + 2
        ang = np.linspace(0, 2 * np.pi * turns, n)
        zc = z0 + hv / 2 - pitch + pitch * ang / (2 * np.pi)
        lo, hi = np.maximum(zc - hv / 2, z0), np.minimum(zc + hv / 2, z1)
        er = np.stack([np.cos(ang), np.sin(ang), 0 * ang], 1)
        rr = 1.06 * self.shaft_r(zc)
        c = self.axis(zc)
        section = ((0.0, 1.0), (0.15, 0.84), (1.8, 0.4), (2.0, 0.06), (0.25, 0.0))
        verts = [c[i] * [1, 1, 0] + er[i] * (rr[i] + dr * th) + [0, 0, lo[i] + f * (hi[i] - lo[i])]
                 for i in range(n) for dr, f in section]
        m = len(section)
        faces = [(i * m + s, i * m + s + 1, (i + 1) * m + s + 1, (i + 1) * m + s) for i in range(n - 1) for s in range(m - 1)]
        pieces = [(verts, faces)]
        for zt in (z0 + 0.004, z1 - 0.004):
            ta = np.linspace(0, 2 * np.pi * 2.5, 30)
            tz = zt + 0.0036 * (ta / (2 * np.pi) - 1.25)
            rad = 1.06 * self.shaft_r(tz) + 2.0 * th + 0.0023
            ring = np.stack([rad * np.cos(ta), rad * np.sin(ta), 0 * ta], 1) + self.axis(tz)
            pieces.append(sweep(ring, np.full(len(ta), 0.0018), 5))
        pieces.append(self.tail(z1 - 0.006, rr.max() + 2.0 * th + 0.0045, th))
        return merge(name, pieces)

    def tail(self, z, r, th, length=0.075, width=0.011, segs=8):
        """Loose strap end hanging from the top tie on the outer side, curling slightly away from the shaft."""
        out = self.base * [1, 1, 0] / max(np.linalg.norm(self.base[:2]), 1e-9)
        tan = np.cross([0, 0, 1.0], out)
        t = np.linspace(0, 1, segs + 1)[:, None]
        spine = self.axis(z) + out * (r + 0.012 * t ** 2) - np.array([0, 0, 1.0]) * length * t
        verts = []
        for p, k in zip(spine, t[:, 0]):
            w = width * (1 - 0.25 * k) / 2
            verts += [p - tan * w, p + tan * w, p + tan * w + out * th, p - tan * w + out * th]
        faces = [(4 * i + s, 4 * i + (s + 1) % 4, 4 * (i + 1) + (s + 1) % 4, 4 * (i + 1) + s) for i in range(segs) for s in range(4)]
        return verts, faces + [(3, 2, 1, 0), tuple(4 * segs + s for s in range(4))]

    def knob(self, name, part):
        """Carved head: a beaded collar, a bulb cut by six narrow spiral grooves, an incised double ring, a cup whose
        rim seats the crystal, and one wooden tendril per claw gap climbing out of the cup to curl in over the gem."""
        rows, ring = 26, 24
        t = np.linspace(0, 1, rows)
        z = self.z_k0 + t * (self.z_k1 - self.z_k0)
        r, kr = float(self.shaft_r(self.z_k0)), self.kr
        prof = np.interp(t, [0, 0.04, 0.08, 0.12, 0.16, 0.3, 0.48, 0.62, 0.7, 0.78, 0.9, 0.97, 1.0],
                         [r, 1.18 * r, 1.22 * r, 1.18 * r, r, 0.95 * kr, 1.18 * kr, 1.02 * kr, 0.86 * kr, 0.88 * kr,
                          1.1 * kr, 1.14 * kr, 1.06 * kr])
        a = 2 * np.pi * np.arange(ring) / ring
        count = self.parts.get('claw', {}).get('count', 3)
        beads = 0.1 * bump(t, 0.08, 0.035)[:, None] * (0.5 + 0.5 * np.cos(12 * a[None])) ** 2
        w = np.sin(np.pi * np.clip((t - 0.18) / 0.5, 0, 1))[:, None]
        groove = (1 - np.abs(np.sin(3 * (a[None] + 2.4 * t[:, None])))) ** 5
        cut = 0.08 * (bump(t, 0.74, 0.012) + bump(t, 0.8, 0.012))[:, None]
        notch = 0.06 * bump(t, 1.0, 0.06)[:, None] * (0.5 + 0.5 * np.cos(count * (a[None] - CLAW_A0))) ** 6
        rr = prof[:, None] * (1 + beads - 0.34 * w * groove - cut - notch)
        verts, faces = sweep(self.axis(z), rr, ring, (False, False))
        top = self.axis(z[-1])
        lip = [top + 0.74 * kr * np.array([math.cos(x), math.sin(x), 0]) + [0, 0, 0.0015] for x in a]
        start = len(verts)
        verts += lip
        faces += [((rows - 1) * ring + s, (rows - 1) * ring + (s + 1) % ring, start + (s + 1) % ring, start + s)
                  for s in range(ring)]
        verts.append(top + [0, 0, -0.004])
        faces += [(start + s, start + (s + 1) % ring, len(verts) - 1) for s in range(ring)]
        pieces = [(verts, faces)] + [self.tendril(CLAW_A0 + np.pi * (2 * i + 1) / count) for i in range(count)]
        return merge(name, pieces)

    def tendril(self, th, rows=16):
        """Wooden root climbing from the bulb's flank, bowing out past the gem, its tapering tip curled onto a facet."""
        t = np.linspace(0, 1, rows)
        z0, z1 = self.z_k1 - 0.04, self.L - 0.42 * self.hc
        z = z0 + (z1 - z0) * (1 - (1 - t) ** 1.25)
        rad = (0.0062 * (1 - t) ** 0.7 + 0.0011) * (1 + 0.3 * bump(t, 0.18, 0.05) + 0.22 * bump(t, 0.5, 0.05))
        wide = float(self.crystal_face_r(self.L - 0.38 * self.hc)) / math.cos(math.pi / 6)
        rho = np.interp(t, [0, 0.3, 0.65, 1.0], [0.92 * self.kr, wide + 0.009, wide + 0.006,
                                                 float(self.crystal_face_r(z1)) + 0.0022])
        ang = th + TENDRIL_TWIST * t
        c = self.axis(z) + rho[:, None] * np.stack([np.cos(ang), np.sin(ang), 0 * t], 1)
        return sweep(c, rad, 6, (False, True))

    def crystal_face_r(self, z):
        """Distance from the axis to the crystal's flat facets at height z (hexagon apothem)."""
        f = (np.asarray(z, float) - (self.L - self.hc)) / self.hc
        return np.interp(f, CRYSTAL_F, CRYSTAL_R) * self.hc * math.cos(math.pi / 6)

    def claw(self, name, part):
        """Silver mount: a beaded ring on the cup rim and talons that root in its notches, swell at three knuckles, run
        up a crystal facet and hook their tips in over the termination; section flattened against the facet."""
        count, length = part.get('count', 3), part.get('size_m', 0.11)
        t = np.linspace(0, 1, 22)
        z0 = self.z_k1 - 0.006
        z = z0 + (0.74 * self.hc + (self.L - self.hc - z0)) * (1 - (1 - t) ** 1.4) * min(1.0, length / 0.11)
        rad = (0.0085 * (1 - t) ** 0.6 + 0.0009) * (1 + sum(0.5 * bump(t, k, 0.028) for k in (0.22, 0.48, 0.7)))
        rho = self.crystal_face_r(z) + 0.6 * rad + 0.0015
        rho = np.where(t < 0.12, np.maximum(rho, 0.9 * self.kr), rho)
        pieces = []
        for i in range(count):
            th = CLAW_A0 + 2 * np.pi * i / count
            radial = np.array([math.cos(th), math.sin(th), 0.0])
            c = self.axis(z) + rho[:, None] * radial
            v, f = sweep(c, rad, 8, (True, True))
            v = np.array(v)
            off = v[:len(c) * 8].reshape(len(c), 8, 3) - c[:, None]
            flat = off - 0.45 * (off @ radial)[..., None] * radial
            v[:len(c) * 8] = (c[:, None] + flat).reshape(-1, 3)
            pieces.append((list(v), f))
        a = np.linspace(0, 2 * np.pi, 37)[:-1]
        rim = self.axis(np.full(36, self.z_k1 - 0.004)) + 1.1 * self.kr * np.stack([np.cos(a), np.sin(a), 0 * a], 1)
        rv, rf = sweep(np.vstack([rim, rim[:1]]), 0.0032 * (1 + 0.25 * np.cos(12 * np.append(a, 0))), 6, (False, False))
        pieces.append((rv, rf))
        return merge(name, pieces)

    def crystal(self, name, part):
        """Faceted crystal cluster: the main gem seated in the cup with an uneven rhombic termination, facets turned to
        the claws, and small satellite crystals breaking out of the cup between claw and tendril; flat shaded, no
        shadow so its light escapes."""
        z0 = self.L - self.hc
        pieces = [self.gem(self.axis(z0), np.array([0, 0, 1.0]), self.hc, CLAW_A0 - 2 * np.pi / 3)]
        count = self.parts.get('claw', {}).get('count', 3)
        for i, (h, tilt, root) in enumerate(SATELLITES):
            th = CLAW_A0 + np.pi * (2 * i + 0.5) / count
            out = np.array([math.cos(th), math.sin(th), 0.0])
            d = math.cos(tilt) * np.array([0, 0, 1.0]) + math.sin(tilt) * out
            base = self.axis(self.z_k1 - 0.006) + out * root * self.kr
            pieces.append(self.gem(base, d, h * self.hc, th + 0.4 * i))
        ob = merge(name, pieces, smooth=False)
        ob.visible_shadow = False
        return ob

    def gem(self, root, d, h, spin):
        """Hexagonal crystal along d from root: rings at CRYSTAL_F heights with fixed facet skew and per-corner radius,
        the last ring's corners staggered up and down so the termination breaks into rhombic facets, an offset apex."""
        u = np.cross(d, [1.0, 0, 0] if abs(d[0]) < 0.9 else [0, 1.0, 0])
        u /= np.linalg.norm(u)
        v = np.cross(d, u)
        a = 2 * np.pi * np.arange(6) / 6 + spin + np.array(CRYSTAL_SKEW)
        corner = 1 + np.array(CRYSTAL_SKEW) * 1.5
        stagger = np.array([0.05, -0.04, 0.03, -0.05, 0.04, -0.03])
        verts = [root + d * CRYSTAL_F[0] * h]
        nr = len(CRYSTAL_F) - 2
        for i, (f, r) in enumerate(zip(CRYSTAL_F[1:-1], CRYSTAL_R[1:-1])):
            lift = stagger if i == nr - 1 else 0
            ring = (r * h * corner)[:, None] * (np.cos(a)[:, None] * u + np.sin(a)[:, None] * v)
            verts += list(root + d * ((f + lift) * h)[..., None] + ring if i == nr - 1 else root + d * f * h + ring)
        verts.append(root + d * h + 0.04 * h * u + 0.02 * h * v)
        faces = [(0, 1 + (s + 1) % 6, 1 + s) for s in range(6)]
        for i in range(nr - 1):
            for s in range(6):
                p, q = 1 + 6 * i + s, 1 + 6 * i + (s + 1) % 6
                faces.append((p, q, q + 6, p + 6))
        tip = len(verts) - 1
        faces += [(1 + 6 * (nr - 1) + s, 1 + 6 * (nr - 1) + (s + 1) % 6, tip) for s in range(6)]
        return verts, faces

    def light(self, name, color, watts):
        ld = bpy.data.lights.new(name, 'POINT')
        ld.energy, ld.color, ld.shadow_soft_size = watts, color, 0.02
        ob = bpy.data.objects.new(name, ld)
        bu.collection('char3d').objects.link(ob)
        ob.location = self.axis(self.L - 0.55 * self.hc)
        return ob


BUILDERS = {'staff': Staff}


def outward(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def linear(hexcol):
    return [((int(hexcol[i:i + 2], 16) / 255 + 0.055) / 1.055) ** 2.4 for i in (1, 3, 5)]


def run(ctx):
    rng = np.random.default_rng(ctx.spec.get('seed', 1032) + 7)
    mats = ctx.spec['materials']
    pulses = {p['material']: p.get('light_w', 60) for p in ctx.spec.get('secondary', {}).get('pulses', [])}
    metrics = {'stub': False, 'parts': 0, 'crystal_emission': 0.0, 'lights': 0, 'tris': 0, 'todo': []}
    for p in ctx.spec['props']:
        if p['kind'] not in BUILDERS:
            raise ValueError(f'props: kind {p["kind"]!r} not built yet (have {sorted(BUILDERS)})')
        grip = None
        if str(p['attach']).startswith('hand.') and 'body' in ctx.parts:
            r = 1.2 * {q['kind']: q for q in p['parts']}.get('shaft', {}).get('size_m', 0.026)
            grip, gap = palm_grip(bpy.data.objects[ctx.parts['body']['object']], ctx.landmarks[p['attach']],
                                  ctx.landmarks['chest'], r)
            metrics[f'{p["id"]}_grip_gap_mm'] = None if gap is None else round(gap * 1000, 1)
        prop = BUILDERS[p['kind']](ctx.spec, p, ctx.landmarks[p['attach']], rng, grip)
        for part in p['parts']:
            pid = f'{p["id"]}.{part["id"]}'
            if not hasattr(prop, part['kind']):
                metrics['todo'].append(f'{pid}:{part["kind"]}')
                continue
            ob = getattr(prop, part['kind'])(pid, part)
            outward(ob)
            ob.data.calc_loop_triangles()
            metrics['tris'] += len(ob.data.loop_triangles)
            ctx.add_part(pid, ob.name, NAME, part['material'], p['attach'])
            metrics['parts'] += 1
            emission = mats.get(part['material'], {}).get('emission')
            if part['kind'] == 'crystal' and emission:
                metrics['crystal_emission'] = max(metrics['crystal_emission'], emission['base'])
                lo = prop.light(f'{p["id"]}.light', linear(mats[part['material']]['color']), pulses.get(part['material'], 60))
                ctx.add_part(lo.name, lo.name, NAME, None, p['attach'])
                metrics['lights'] += 1
                metrics['light_w'] = lo.data.energy
        metrics[f'{p["id"]}_grip'] = [round(float(v), 4) for v in prop.grip]
        metrics[f'{p["id"]}_base'] = [round(float(v), 4) for v in prop.base]
    metrics['stub'] = bool(metrics['todo'])
    return metrics

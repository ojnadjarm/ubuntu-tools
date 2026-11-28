"""film qa turntable: a column, an arch and a hanging chain on a turn, made by code (numpy only: Blender reads it too)."""
import zlib

import numpy as np

from atelier.anchor import SeedBank, concat
from atelier.scene import Camera, Light, Mesh, ident_of

SIZE = (480, 270)
RHO0, OCTAVES = 0.25, 9
HEX = np.array([[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6], [0, 1, 4], [1, 5, 4],
                [2, 6, 3], [3, 6, 7], [0, 4, 2], [2, 4, 6], [1, 3, 5], [3, 7, 5]])  # outward, corners by bits (x, y, z)


def box(lo, hi):
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    return np.array([[x, y, z] for z in (0, 1) for y in (0, 1) for x in (0, 1)], float) * (hi - lo) + lo


def stone(cx, cz, r0, r1, t0, t1, d):
    """An arch stone between radii r0, r1 and angles t0, t1 (rad, in the x-z plane), d deep: corners by bits (r, y, angle)."""
    return np.array([[cx + r * np.cos(t), y, cz + r * np.sin(t)] for t in (t0, t1) for y in (-d, d) for r in (r0, r1)])


def parts():
    """(name, material, corners) of the floor, the column, the arch (two piers, nine stones) and the chain's links."""
    out = [("floor", "stone", box([-4, -4, -0.2], [4, 4, 0])), ("column", "stone", box([-1.8, -0.3, 0], [-1.2, 0.3, 3.0])),
           ("pier0", "stone", box([0.3, -0.3, 0], [0.7, 0.3, 2.0])), ("pier1", "stone", box([2.8, -0.3, 0], [3.2, 0.3, 2.0]))]
    out += [("stone%d" % i, "stone", stone(1.75, 2.0, 1.05, 1.45, np.pi * (1 - (i + 1) / 9), np.pi * (1 - i / 9), 0.3))
            for i in range(9)]
    for i in range(8):  # links turned a quarter each, hanging from the arch's crown
        c, turn = np.array([1.75, 0.0, 2.95 - 0.13 * i]), i % 2
        V = box([-0.035, -0.012, -0.08], [0.035, 0.012, 0.08])
        out.append(("link%d" % i, "iron", c + (V[:, [1, 0, 2]] * [-1, 1, 1] if turn else V)))
    return out


class TurnTable:
    fps, duration = 24, 1.0
    materials = {"stone": {"color": (0.42, 0.40, 0.37), "rough": 0.8},
                 "iron": {"color": (0.10, 0.10, 0.11), "metal": 1.0, "rough": 0.4}}
    world = {"color": (0.05, 0.06, 0.09), "strength": 0.6, "haze": 0.0}

    def meshes(self, t):
        return [Mesh(n, V.astype(np.float32), HEX.astype(np.int32), m,
                     {"tone": np.ones(8, np.float32), "ident": np.full(8, int(ident_of(0, i + 1)), np.int64)})
                for i, (n, m, V) in enumerate(parts())]

    def seeds(self, t, cam, px_per_stroke):
        if not hasattr(self, "_banks"):
            mats = sorted(self.materials)
            self._banks = [(m.V, SeedBank(m.V, m.F, mats.index(m.material), m.attrs["ident"], "course", RHO0,
                                          zlib.crc32(m.name.encode()), OCTAVES)) for m in self.meshes(0.0)]
        return concat([b.place(V, cam, px_per_stroke) for V, b in self._banks])

    def camera(self, t):
        a = 2 * np.pi * t / self.duration - np.pi / 2
        return Camera.aim([0.5 + 7.5 * np.cos(a), 7.5 * np.sin(a), 2.4], [0.5, 0.0, 1.5], 0.0, 30.0, SIZE)

    def lights(self, t):
        return [Light("sun", rot=(0.7, 0.3, 0.4), color=(0.7, 0.78, 1.0), watts=2.0, radius=0.05),
                Light("point", pos=(1.75, -1.5, 2.6), color=(1.0, 0.6, 0.3), watts=200.0, radius=0.1)]

    def events(self):
        return {}


def scene():
    return TurnTable()

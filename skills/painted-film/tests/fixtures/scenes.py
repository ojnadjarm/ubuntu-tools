"""Small code-made scenes for the reference tests: dots at known places, and a hazy lamp-lit room."""
import numpy as np

from atelier.scene import Camera, Light, Mesh, ident_of


def sphere(c, r, n=16):
    """A UV sphere: verts and outward triangles."""
    th, ph = np.linspace(0, np.pi, n + 1)[1:-1], np.linspace(0, 2 * np.pi, 2 * n, endpoint=False)
    V = [[0, 0, 1.0]] + [[np.sin(a) * np.cos(b), np.sin(a) * np.sin(b), np.cos(a)] for a in th for b in ph] + [[0, 0, -1.0]]
    m, F = len(ph), []
    for i in range(m):
        F.append([0, 1 + i, 1 + (i + 1) % m])
    for k in range(len(th) - 1):
        for i in range(m):
            a, b, c2, d = 1 + k * m + i, 1 + k * m + (i + 1) % m, 1 + (k + 1) * m + i, 1 + (k + 1) * m + (i + 1) % m
            F += [[a, c2, d], [a, d, b]]
    last = len(V) - 1
    for i in range(m):
        F.append([last, 1 + (len(th) - 1) * m + (i + 1) % m, 1 + (len(th) - 1) * m + i])
    return np.array(V) * r + np.asarray(c, float), np.array(F)


def box(lo, hi, inward=False):
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    V = np.array([[x, y, z] for z in (0, 1) for y in (0, 1) for x in (0, 1)], float) * (hi - lo) + lo
    F = np.array([[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6], [0, 1, 4], [1, 5, 4],
                  [2, 6, 3], [3, 6, 7], [0, 4, 2], [2, 4, 6], [1, 3, 5], [3, 7, 5]])
    return V, (F[:, ::-1] if inward else F)


def mesh(name, V, F, material, ident, tone=1.0):
    n = len(V)
    return Mesh(name, V.astype(np.float32), F.astype(np.int32), material,
                {"tone": np.full(n, tone, np.float32), "ident": np.full(n, ident, np.int64)})


class Base:
    fps, duration = 24, 1.0
    size = (480, 270)

    def seeds(self, t, cam, px_per_stroke):
        raise NotImplementedError

    def events(self):
        return {}


class Dots(Base):
    """Ten small spheres at known places, each its own ident, before a wall 10 m away on the lower part of the view."""
    POINTS = np.array([[-1.6, 5.0, 0.6], [-0.8, 6.0, 0.9], [0.0, 5.0, 0.3], [0.9, 7.0, 1.2], [1.7, 5.5, 0.7],
                       [-1.2, 8.0, -0.4], [-0.3, 4.5, -0.5], [0.6, 6.5, -0.2], [1.4, 4.8, -0.6], [2.4, 9.0, 1.6]])
    IDENTS = [int(ident_of(i % 3, 100 + 37 * i)) for i in range(10)]
    WALL = 10.0
    materials = {"dot": {"color": (0.6, 0.3, 0.2)}, "wall": {"color": (0.3, 0.3, 0.3)}}
    world = {"color": (0.1, 0.2, 0.3), "strength": 1.0, "haze": 0.0}

    def meshes(self, t):
        out = [mesh("dot%d" % i, *sphere(p, 0.06), "dot", k) for i, (p, k) in enumerate(zip(self.POINTS, self.IDENTS))]
        V = np.array([[-20, self.WALL, -12], [20, self.WALL, -12], [20, self.WALL, -1.6], [-20, self.WALL, -1.6]], float)
        out.append(mesh("wall", V, np.array([[0, 2, 1], [0, 3, 2]]), "wall", 5))
        return out

    def camera(self, t):
        return Camera.aim([0.0, 0.0, 0.0], [0.0, 1.0, 0.0], 0.0, 40.0, self.size)

    def lights(self, t):
        return [Light("sun", rot=(0.6, 0.2, 0.0), watts=3.0, radius=0.05)]


class Room(Base):
    """A hazy lamp-lit room (960x540) with The Well's haze and lamp settings: the reference noise of such a set."""
    size = (960, 540)
    materials = {"stone": {"color": (0.12, 0.13, 0.15)}, "glow": {"color": (1.0, 0.56, 0.2), "emission": 60.0}}
    world = {"color": (0.05, 0.075, 0.13), "strength": 0.5, "haze": 0.02, "anisotropy": 0.35}

    def meshes(self, t):
        out = [mesh("room", *box([-6, -2, 0], [6, 14, 6], inward=True), "stone", 1)]
        for i, (x, y, s) in enumerate(((-2.5, 6, 1.2), (1.5, 8, 1.6), (3.5, 5, 0.8), (-1.0, 10, 2.0))):
            out.append(mesh("block%d" % i, *box([x - s / 2, y - s / 2, 0], [x + s / 2, y + s / 2, 2 * s]), "stone", 2 + i, 0.8 + 0.1 * i))
        for i, p in enumerate(((-3.0, 7.0, 3.5), (2.5, 10.0, 4.0))):
            out.append(mesh("flame%d" % i, *sphere(p, 0.08, 8), "glow", int(ident_of(1, 10 + i))))
        return out

    def camera(self, t):
        return Camera.aim([0.0, -1.0, 1.7], [0.0, 10.0, 1.5], 0.0, 22.0, self.size)

    def lights(self, t):
        return [Light("point", pos=(-3.0, 7.0, 3.3), color=(1.0, 0.56, 0.2), watts=120.0, radius=0.07, haze=0.25),
                Light("point", pos=(2.5, 10.0, 3.8), color=(1.0, 0.56, 0.2), watts=120.0, radius=0.07, haze=0.25),
                Light("area", pos=(0.0, 4.0, 5.8), color=(0.5, 0.64, 1.0), watts=150.0, radius=4.0, shadow=False, haze=0.0)]


class Stained(Base):
    """A wall facing the camera, its material a white stone with a black layer, lit by one spot at its middle."""
    materials = {"wall": {"color": (0.8, 0.8, 0.8), "layers": [{"color": (0.0, 0.0, 0.0), "scale": 1.0, "lo": 0.45, "hi": 0.55}]}}
    world = {"color": (0.0, 0.0, 0.0), "strength": 0.0, "haze": 0.0}

    def meshes(self, t):
        V = np.array([[-20, 10, -12], [20, 10, -12], [20, 10, 12], [-20, 10, 12]], float)
        return [mesh("wall", V, np.array([[0, 2, 1], [0, 3, 2]]), "wall", 5)]

    def camera(self, t):
        return Camera.aim([0.0, 0.0, 0.0], [0.0, 1.0, 0.0], 0.0, 40.0, self.size)

    def lights(self, t):
        return [Light("spot", pos=(0.0, 0.0, 0.0), rot=(np.pi / 2, 0.0, 0.0), watts=5000.0, cone=0.3, blend=0.1, shadow=False)]


class Beside(Stained):
    """The wall plain, a plate that is not in the picture between it and the spot, a block of haze in the left of the cone."""
    materials = {"wall": {"color": (0.8, 0.8, 0.8)}, "plate": {"color": (0, 0, 0), "unseen": True}, "mist": {"color": (1, 1, 1), "haze": 2.0}}

    def meshes(self, t):
        q = np.array([[-3, 5, -3], [3, 5, -3], [3, 5, 3], [-3, 5, 3]], float)
        b = np.array([[x, y, z] for x in (-1.0, -0.1) for y in (2.0, 4.0) for z in (-0.5, 0.5)])
        F = np.array([[0, 1, 3], [0, 3, 2], [4, 7, 5], [4, 6, 7], [0, 5, 1], [0, 4, 5], [2, 3, 7], [2, 7, 6], [0, 2, 6], [0, 6, 4], [1, 5, 7], [1, 7, 3]])
        return super().meshes(t) + [mesh("plate", q, np.array([[0, 2, 1], [0, 3, 2]]), "plate", 6), mesh("mist", b, F, "mist", 7)]

    def lights(self, t):
        return [Light("spot", pos=(0.0, 0.0, 0.0), rot=(np.pi / 2, 0.0, 0.0), watts=5000.0, cone=0.3, blend=0.1, shadow=True)]

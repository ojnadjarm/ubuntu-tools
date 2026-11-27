"""The scene types (Mesh, Camera, Light, Seeds), the Scene protocol and the ident code (numpy only: runs in Blender too)."""
from dataclasses import dataclass, field
from typing import Protocol

import numpy as np

RULE_SHIFT = 20  # ident = rule << 20 | index; rule 0 plain, 1 emitter, 2.. the film's own colour rules
RULE_EMITTER = 1
IDENT_MAX = 1 << 24  # the ident pass carries 24 bits


def ident_of(rule, index):
    """Ident of a thing: its colour rule in the high bits, its index (< 2^20) in the low ones."""
    return (np.asarray(rule, np.int64) << RULE_SHIFT) | np.asarray(index, np.int64)


def rule_of(ident):
    return np.asarray(ident, np.int64) >> RULE_SHIFT


def _check(ident):
    """A hash of the ident on a 1/1024 grid in [0, 1) (exact in half floats): a blend of two codes does not match it."""
    with np.errstate(over="ignore"):  # splitmix64, wrapping on purpose: no linear trace a blend could follow
        h = np.asarray(ident, np.uint64) + np.uint64(0x9E3779B97F4A7C15)
        h = (h ^ (h >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        h = (h ^ (h >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        h = h ^ (h >> np.uint64(31))
    return (h >> np.uint64(54)).astype(np.float64) / 1024.0


def ident_code(ident):
    """(n, 4) float32 the ident pass writes: the ident's three bytes and a check. EEVEE keeps AOVs as half floats,
    which hold these values exactly; an anti-aliased edge blends codes into values that fail the check."""
    i = np.asarray(ident, np.int64)
    return np.column_stack([(i >> 16) & 255, (i >> 8) & 255, i & 255, _check(i)]).astype(np.float32)


def ident_decode(code):
    """(..., 4) code -> (ident, clean): clean where the code is one ident's, not a blend of several."""
    code = np.asarray(code, np.float64)
    b = np.rint(code[..., :3])
    ident = (np.clip(b, 0, 255).astype(np.int64) * [1 << 16, 1 << 8, 1]).sum(-1)
    clean = (np.abs(code[..., :3] - b) < 0.02).all(-1) & (np.abs(code[..., 3] - _check(ident)) < 1e-4)
    return ident, clean


@dataclass
class Mesh:
    name: str
    V: np.ndarray  # (n, 3) f32
    F: np.ndarray  # (m, 3) i32
    material: str
    attrs: dict = field(default_factory=dict)  # per vertex: "tone" (n,), "ident" (n,)


@dataclass
class Camera:
    pos: np.ndarray  # (3,)
    R: np.ndarray  # (3, 3) world from camera: columns right, up, back (the view looks down -column 2)
    lens_mm: float
    sensor_mm: float
    size: tuple  # (W, H) px; the sensor width spans W

    @classmethod
    def aim(cls, pos, aim, roll, lens_mm, size, sensor_mm=36.0, up=(0.0, 0.0, 1.0)):
        """A camera at pos looking at aim, turned by roll (rad) about its view axis."""
        pos, aim = np.asarray(pos, float), np.asarray(aim, float)
        fw = (aim - pos) / np.linalg.norm(aim - pos)
        right = np.cross(fw, up)
        right /= np.linalg.norm(right)
        u = np.cross(right, fw)
        right, u = right * np.cos(roll) + u * np.sin(roll), u * np.cos(roll) - right * np.sin(roll)
        return cls(pos, np.column_stack([right, u, -fw]), float(lens_mm), float(sensor_mm), tuple(int(v) for v in size))

    def project(self, P):
        """World points (k, 3) -> pixel places (k, 2) (pixel (i, j) has its centre at x = j, y = i) and view depth (k,)."""
        c = (np.asarray(P, float) - self.pos) @ self.R
        z = -c[:, 2]
        W, H = self.size
        f = self.lens_mm / self.sensor_mm * W
        with np.errstate(divide="ignore", invalid="ignore"):
            xy = np.column_stack([W / 2 - 0.5 + f * c[:, 0] / z, H / 2 - 0.5 - f * c[:, 1] / z])
        return xy, z

    def to_json(self):
        return dict(pos=self.pos.tolist(), R=self.R.tolist(), lens_mm=self.lens_mm, sensor_mm=self.sensor_mm, size=list(self.size))

    @classmethod
    def from_json(cls, d):
        return cls(np.array(d["pos"], float), np.array(d["R"], float), d["lens_mm"], d["sensor_mm"], tuple(d["size"]))


@dataclass
class Light:
    kind: str  # "point" | "sun" | "area"
    pos: tuple = (0.0, 0.0, 0.0)
    rot: tuple = (0.0, 0.0, 0.0)  # Euler XYZ, rad (sun and area aim down their local -z)
    color: tuple = (1.0, 1.0, 1.0)
    watts: float = 100.0  # sun: strength in W/m2
    radius: float = 0.1  # point: m; sun: angular diameter, rad; area: edge of the square, m
    shadow: bool = True
    haze: float = 1.0  # how much it lights the haze (volume factor)


@dataclass
class Seeds:
    id: np.ndarray  # (k,) u64
    P: np.ndarray  # (k, 3)
    N: np.ndarray  # (k, 3)
    T: np.ndarray  # (k, 3) unit, along the stroke
    octave: np.ndarray  # (k,) u8
    material: np.ndarray  # (k,) i16
    ident: np.ndarray  # (k,) i32
    kind: np.ndarray  # (k,) u8: 0 fill, 1 mark
    width_m: np.ndarray  # (k,) f32, marks only
    length_m: np.ndarray  # (k,) f32, marks only
    rule: np.ndarray  # (k,) u8, colour rule
    opacity: np.ndarray  # (k,) f32, the octave fade (A4)
    px: np.ndarray  # (k,) f32, screen spacing of the seed's octave at its place (A4)


class Scene(Protocol):
    fps: int
    duration: float
    materials: dict  # name -> {"color": (r, g, b), "emission": strength, "rough": 0..1, "metal": 0..1}
    world: dict  # {"color": (r, g, b), "strength", "haze": density, "anisotropy", "air": (r, g, b), "air_strength"}

    def meshes(self, t: float) -> list: ...

    def seeds(self, t: float, cam: Camera, px_per_stroke: float) -> Seeds: ...

    def camera(self, t: float) -> Camera: ...

    def lights(self, t: float) -> list: ...

    def events(self) -> dict: ...

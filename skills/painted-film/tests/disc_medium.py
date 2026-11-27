"""A flat-disc test medium: each stroke an anti-aliased ellipse of its colour, drawn in the strokes' order (A4)."""
import numpy as np


class DiscMedium:
    canvas = (0.18, 0.17, 0.16)  # display colour where no stroke lands

    def composite(self, strokes, ref, look, size):
        """Strokes -> uint8 RGB picture of `size`; float accumulation, one rounding at the end."""
        W, H = size
        img = np.empty((H, W, 3), np.float32)
        img[:] = self.canvas
        col = np.clip(strokes.c1, 0.0, 1.0) ** (1 / 2.2)
        for x, y, ang, L, w, c, op in zip(strokes.x, strokes.y, strokes.ang, strokes.length, strokes.width, col,
                                          strokes.opacity):
            a, b = max(L / 2, 0.5), max(w / 2, 0.5)
            R = a + 1.0
            x0, x1 = max(int(np.floor(x - R)), 0), min(int(np.ceil(x + R)) + 1, W)
            y0, y1 = max(int(np.floor(y - R)), 0), min(int(np.ceil(y + R)) + 1, H)
            if x0 >= x1 or y0 >= y1:
                continue
            dx = np.arange(x0, x1, dtype=np.float32)[None, :] - x
            dy = np.arange(y0, y1, dtype=np.float32)[:, None] - y
            ca, sa = np.cos(ang), np.sin(ang)
            u, v = dx * ca + dy * sa, -dx * sa + dy * ca
            q = np.sqrt((u / a) ** 2 + (v / b) ** 2)
            g = np.sqrt((u / (a * a)) ** 2 + (v / (b * b)) ** 2) / np.maximum(q, 1e-6)
            cov = np.clip(0.5 - (q - 1.0) / np.maximum(g, 1e-6), 0.0, 1.0)[..., None] * op
            patch = img[y0:y1, x0:x1]
            patch += cov * (c - patch)
        return np.round(np.clip(img, 0.0, 1.0) * 255).astype(np.uint8)

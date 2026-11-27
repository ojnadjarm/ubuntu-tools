"""How far a frame is from the target as a painting: value, palette, edges, density (RESEARCH 1.1, A1 to A7)."""
import cv2
import numpy as np

H = 1080


def _norm(a):
    return cv2.resize(a, (int(round(a.shape[1] * H / a.shape[0])), H), interpolation=cv2.INTER_AREA if a.shape[0] > H else cv2.INTER_CUBIC)


def stats(a):
    """The measures of one BGR uint8 picture at 1080 px high, and its Lab pixels."""
    lab = cv2.cvtColor(_norm(a).astype(np.float32) / 255.0, cv2.COLOR_BGR2Lab)
    L = lab[..., 0]
    ch = np.hypot(lab[..., 1], lab[..., 2])
    out = dict(L_mean=L.mean(), L_p05=np.percentile(L, 5), L_p50=np.percentile(L, 50), L_p95=np.percentile(L, 95),
               dark=(L < 25).mean() * 100, mid=((L >= 25) & (L < 60)).mean() * 100, light=(L >= 60).mean() * 100,
               chroma_mean=ch.mean(), warm=((lab[..., 2] > 8) & (ch > 12)).mean() * 100,
               cool=((lab[..., 2] < -4) & (ch > 6)).mean() * 100)
    g = cv2.GaussianBlur(L, (0, 0), 1.0)
    mag = np.hypot(cv2.Sobel(g, cv2.CV_32F, 1, 0) / 8, cv2.Sobel(g, cv2.CV_32F, 0, 1) / 8)
    ed = cv2.Canny((L * 2.55).astype(np.uint8), 40, 100) > 0
    out["edge_px"] = ed.mean() * 100
    nx = ed.shape[1] // 120
    t = ed[:, :nx * 120].reshape(H // 120, 120, nx, 120).mean((1, 3)) * 100
    out["empty_tiles"] = (t < 1.0).mean() * 100
    out["tile_edge_p50"] = np.percentile(t, 50)
    lo, hi = cv2.erode(g, np.ones((9, 9))), cv2.dilate(g, np.ones((9, 9)))
    wid = (hi - lo)[ed] / np.maximum(mag[ed], 1e-3)
    out["edge_hard"] = (wid < 2.5).mean() * 100 if wid.size else 0.0
    out["edge_soft"] = (wid > 5).mean() * 100 if wid.size else 0.0
    b = [L] + [cv2.GaussianBlur(L, (0, 0), s) for s in (2, 8, 32)]
    for name, i in (("fine", 0), ("mid", 1), ("broad", 2)):
        out["band_" + name] = np.abs(b[i] - b[i + 1]).mean()
    hist = np.histogram(cv2.GaussianBlur(L, (0, 0), 24), bins=10, range=(0, 100))[0] / L.size
    out["top3_value"] = np.sort(hist)[-3:].sum() * 100
    return {k: float(v) for k, v in out.items()}, lab


def swd(a, b, n=64, seed=1):
    """Sliced Wasserstein distance between two Lab pixel clouds (Lab units); seeded, so a picture against itself is 0."""
    k = min(60000, a.shape[0] * a.shape[1], b.shape[0] * b.shape[1])
    a = a.reshape(-1, 3)[np.random.default_rng(seed).choice(a.shape[0] * a.shape[1], k, replace=False)]
    b = b.reshape(-1, 3)[np.random.default_rng(seed).choice(b.shape[0] * b.shape[1], k, replace=False)]
    d = np.random.default_rng(seed + 1).normal(size=(n, 3))
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    return float(np.mean([np.abs(np.sort(a @ v) - np.sort(b @ v)).mean() for v in d]))


def lookdist(frame, target) -> dict:
    """The frame's measures plus palette_dist to the target; frame and target are BGR uint8 arrays."""
    s, lab = stats(frame)
    _, tl = stats(target)
    s["palette_dist"] = swd(tl, lab)
    return s

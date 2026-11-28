/* Stroke compositor of the oil medium, from oil-paint's oilc.c: inverse-warps each bristle sprite (bilinear, pyramid
   level by scale) and lays it on the frame (colour over, paint height partly levelled then added). A5: each sprite pixel
   is depth-tested: the stroke's plane depth there against dmax, the reference depth dilated by edge_spill_px.
   T2038: a stroke with a normal sn is cut to its own face (the reference normal nref agrees with sn, ramp f0..f1) and
   to dmin (the reference depth eroded: how far it may hang over its outline); hard steepens the sprite's alpha.
   T2047: with smax / smin, dmax and dmin reach one pixel further and each pixel holds its share within the cut's own
   reach (from the outline's coverage): the spill and overhang cuts move with the outline's sub-pixel place. */
#include <math.h>

#define MAXLEV 8

/* The sprite (alpha, streak, height) averaged over one picture pixel's footprint in sprite pixels (du by dv about
   u, v): nu by nv bilinear taps, those off the sprite count as empty. A stroke thinner than its sprite's pixels is read
   as an area, never at one point (rules 7 and 9). */
static void foot(const float *m, int mw, int mh, float u, float v, float du, float dv, float *out)
{
    int nu = (int)ceilf(du), nv = (int)ceilf(dv);
    if (nu < 1) nu = 1;
    if (nu > 4) nu = 4;
    if (nv < 1) nv = 1;
    if (nv > 16) nv = 16;
    float a = 0.0f, st = 0.0f, he = 0.0f;
    for (int j = 0; j < nv; j++) {
        float vv = nv > 1 ? v + dv * ((j + 0.5f) / nv - 0.5f) : v;
        if (vv < 0.0f || vv >= mh - 1.001f) continue;
        for (int i = 0; i < nu; i++) {
            float uu = nu > 1 ? u + du * ((i + 0.5f) / nu - 0.5f) : u;
            if (uu < 0.0f || uu >= mw - 1.001f) continue;
            int iu = (int)uu, iv = (int)vv;
            float fu = uu - iu, fv = vv - iv;
            const float *p00 = m + ((long)iv * mw + iu) * 3;
            const float *p01 = p00 + 3, *p10 = p00 + (long)mw * 3, *p11 = p10 + 3;
            float w00 = (1 - fu) * (1 - fv), w01 = fu * (1 - fv), w10 = (1 - fu) * fv, w11 = fu * fv;
            a += p00[0] * w00 + p01[0] * w01 + p10[0] * w10 + p11[0] * w11;
            st += p00[1] * w00 + p01[1] * w01 + p10[1] * w10 + p11[1] * w11;
            he += p00[2] * w00 + p01[2] * w01 + p10[2] * w10 + p11[2] * w11;
        }
    }
    float k = 1.0f / (nu * nv);
    out[0] = a * k;
    out[1] = st * k;
    out[2] = he * k;
}

/* A depth test's ramp r (about 2 at the surface the cut depth holds, 4 or more clearly on the passing side) with the
   pixel's share s of that surface's reach: a stroke on that surface gets s, one clearly past it all. */
static float reach(float r, const float *s, long q)
{
    if (r <= 0.0f) return 0.0f;
    float v = r < 1.0f ? r : 1.0f;
    if (!s) return v;
    float t = r - 3.0f;
    t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
    return v * (s[q] + (1.0f - s[q]) * t);
}

void paint_strokes(float *img, float *hgt, int W, int H, const float *atlas, const int *off, const int *mw_, const int *mh_,
                   const int *nlev, const float *body_w, float L, int n, const float *x, const float *y, const float *ang,
                   const float *len, const float *wid, const int *var, const float *c1, const float *c2, const float *op,
                   const float *hs, float level, const float *dmax, const float *z, const float *zg, const float *nref,
                   const float *sn, float f0, float f1, const float *dmin, float hard, const float *smax,
                   const float *smin)
{
    for (int i = 0; i < n; i++) {
        float o = op[i];
        if (o <= 0.004f || wid[i] <= 0.0f) continue;
        int k = var[i];
        float sx = len[i] / L;
        /* rule 5: the sprite's level is a ramp between two levels, never a choice that jumps as the length changes;
           centred half a level finer than the old choice (lev with sx 2^(lev+1) <= 1.25), so as sharp on the whole */
        float lam = log2f(0.4419417f / sx);
        if (lam < 0.0f) lam = 0.0f;
        if (lam > (float)(nlev[k] - 1)) lam = (float)(nlev[k] - 1);
        int lev = (int)lam, lev2 = lev + 1 < nlev[k] ? lev + 1 : lev;
        float fr = lam - (float)lev;
        int li = k * MAXLEV + lev, li2 = k * MAXLEV + lev2;
        const float *m2 = atlas + off[li2];
        int mw2 = mw_[li2], mh2 = mh_[li2];
        float sc2 = (float)(1 << lev2);
        float isx2 = L / sc2 / len[i], isy2 = body_w[k] / sc2 / wid[i], cmx2 = mw2 * 0.5f, cmy2 = mh2 * 0.5f;
        const float *m = atlas + off[li];
        int mw = mw_[li], mh = mh_[li];
        float sc = (float)(1 << lev);
        float sxl = len[i] / (L / sc), syl = wid[i] / (body_w[k] / sc);
        float c = cosf(ang[i]), s = sinf(ang[i]);
        float hw = 0.5f * (fabsf(c) * mw * sxl + fabsf(s) * mh * syl);
        float hh = 0.5f * (fabsf(s) * mw * sxl + fabsf(c) * mh * syl);
        float cx = x[i], cy = y[i];
        float iz0 = 1.0f / z[i], gx = zg[2 * i], gy = zg[2 * i + 1], izlo = 0.5f * iz0, izhi = iz0 / 0.75f;
        int x0 = (int)floorf(cx - hw) - 1, x1 = (int)ceilf(cx + hw) + 1;
        int y0 = (int)floorf(cy - hh) - 1, y1 = (int)ceilf(cy + hh) + 1;
        if (x1 < 0 || y1 < 0 || x0 >= W || y0 >= H) continue;
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 > W - 1) x1 = W - 1;
        if (y1 > H - 1) y1 = H - 1;
        float isx = 1.0f / sxl, isy = 1.0f / syl, cmx = mw * 0.5f, cmy = mh * 0.5f;
        float r1 = c1[3 * i], g1 = c1[3 * i + 1], b1 = c1[3 * i + 2];
        float dr = c2[3 * i] - r1, dg = c2[3 * i + 1] - g1, db = c2[3 * i + 2] - b1;
        float hsc = o * hs[i] * wid[i] * 0.5f;
        float nx = sn[3 * i], ny = sn[3 * i + 1], nz = sn[3 * i + 2];
        int cut = nx * nx + ny * ny + nz * nz > 0.25f;
        float ulo = (0.0f - cmx) / isx - 1.0f, uhi = (mw - 1.001f - cmx) / isx + 1.0f;
        float vlo = (0.0f - cmy) / isy - 1.0f, vhi = (mh - 1.001f - cmy) / isy + 1.0f;
        for (int py = y0; py <= y1; py++) {
            float dy = py - cy;
            float *row = img + (long)py * W * 3;
            float *hrow = hgt + (long)py * W;
            /* the px range where the sprite's rectangle covers this row: u = c dx + s dy in [ulo, uhi], v = -s dx + c dy in [vlo, vhi] */
            float lo = -1e9f, hi = 1e9f, a0, a1;
            if (fabsf(c) > 1e-6f) { a0 = (ulo - s * dy) / c; a1 = (uhi - s * dy) / c; if (a0 > a1) { float t = a0; a0 = a1; a1 = t; } lo = fmaxf(lo, a0); hi = fminf(hi, a1); }
            else if (s * dy < ulo || s * dy > uhi) continue;
            if (fabsf(s) > 1e-6f) { a0 = (vlo - c * dy) / -s; a1 = (vhi - c * dy) / -s; if (a0 > a1) { float t = a0; a0 = a1; a1 = t; } lo = fmaxf(lo, a0); hi = fminf(hi, a1); }
            else if (c * dy < vlo || c * dy > vhi) continue;
            int qa = (int)ceilf(cx + lo), qb = (int)floorf(cx + hi);
            if (qa < x0) qa = x0;
            if (qb > x1) qb = x1;
            for (int px = qa; px <= qb; px++) {
                float dx = px - cx;
                float u = (c * dx + s * dy) * isx + cmx;
                float v = (-s * dx + c * dy) * isy + cmy;
                float f1v[3], f2v[3] = {0.0f, 0.0f, 0.0f};
                foot(m, mw, mh, u, v, isx, isy, f1v);
                if (fr > 0.0f)
                    foot(m2, mw2, mh2, (c * dx + s * dy) * isx2 + cmx2, (-s * dx + c * dy) * isy2 + cmy2, isx2, isy2, f2v);
                float a = f1v[0] + (f2v[0] - f1v[0]) * fr;
                float st = f1v[1] + (f2v[1] - f1v[1]) * fr;
                float he = f1v[2] + (f2v[2] - f1v[2]) * fr;
                if (a < 0.002f) continue;
                a = fminf(a * hard, 1.0f);
                /* the plane's depth here, kept within [0.75, 2] times the stroke's own (grazing planes) */
                float iz = fminf(fmaxf(iz0 + gx * dx + gy * dy, izlo), izhi), zt = 1.0f / iz;
                long pq = (long)py * W + px;
                float vis = reach((dmax[pq] - zt) / (0.005f + 0.005f * zt) + 2.0f, smax, pq);
                if (vis <= 0.0f) continue;
                if (vis < 1.0f) a *= vis;
                if (cut) {
                    if (dmin) {
                        vis = reach((zt - dmin[pq]) / (0.005f + 0.005f * zt) + 2.0f, smin, pq);
                        if (vis <= 0.0f) continue;
                        if (vis < 1.0f) a *= vis;
                    }
                    const float *nr = nref + ((long)py * W + px) * 3;
                    float l2 = nr[0] * nr[0] + nr[1] * nr[1] + nr[2] * nr[2];
                    if (f1 > f0 && l2 > 0.04f) {
                        vis = ((nr[0] * nx + nr[1] * ny + nr[2] * nz) / sqrtf(l2) - f0) / (f1 - f0);
                        if (vis <= 0.0f) continue;
                        if (vis < 1.0f) a *= vis;
                    }
                }
                a *= o;
                float *q = row + px * 3;
                q[0] += (r1 + dr * st - q[0]) * a;
                q[1] += (g1 + dg * st - q[1]) * a;
                q[2] += (b1 + db * st - q[2]) * a;
                hrow[px] = hrow[px] * (1.0f - level * a) + he * hsc;
            }
        }
    }
}

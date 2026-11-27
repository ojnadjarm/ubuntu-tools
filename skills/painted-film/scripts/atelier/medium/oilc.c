/* Stroke compositor of the oil medium, from oil-paint's oilc.c: inverse-warps each bristle sprite (bilinear, pyramid
   level by scale) and lays it on the frame (colour over, paint height partly levelled then added). A5: each sprite pixel
   is depth-tested: the stroke's plane depth there against dmax, the reference depth dilated by edge_spill_px. */
#include <math.h>

#define MAXLEV 8

void paint_strokes(float *img, float *hgt, int W, int H, const float *atlas, const int *off, const int *mw_, const int *mh_,
                   const int *nlev, const float *body_w, float L, int n, const float *x, const float *y, const float *ang,
                   const float *len, const float *wid, const int *var, const float *c1, const float *c2, const float *op,
                   const float *hs, float level, const float *dmax, const float *z, const float *zg)
{
    for (int i = 0; i < n; i++) {
        float o = op[i];
        if (o <= 0.004f || wid[i] < 0.6f) continue;
        int k = var[i];
        float sx = len[i] / L;
        int lev = 0;
        while (lev + 1 < nlev[k] && sx * (float)(1 << (lev + 1)) <= 1.25f) lev++;
        int li = k * MAXLEV + lev;
        const float *m = atlas + off[li];
        int mw = mw_[li], mh = mh_[li];
        float sc = (float)(1 << lev);
        float sxl = len[i] / (L / sc), syl = wid[i] / (body_w[k] / sc);
        float c = cosf(ang[i]), s = sinf(ang[i]);
        float hw = 0.5f * (fabsf(c) * mw * sxl + fabsf(s) * mh * syl);
        float hh = 0.5f * (fabsf(s) * mw * sxl + fabsf(c) * mh * syl);
        float cx = x[i], cy = y[i];
        float iz0 = 1.0f / z[i], gx = zg[2 * i], gy = zg[2 * i + 1], izlo = 0.5f * iz0, izhi = iz0 / 0.75f;
        int x0 = (int)floorf(cx - hw), x1 = (int)ceilf(cx + hw);
        int y0 = (int)floorf(cy - hh), y1 = (int)ceilf(cy + hh);
        if (x1 < 0 || y1 < 0 || x0 >= W || y0 >= H) continue;
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 > W - 1) x1 = W - 1;
        if (y1 > H - 1) y1 = H - 1;
        float isx = 1.0f / sxl, isy = 1.0f / syl, cmx = mw * 0.5f, cmy = mh * 0.5f;
        float r1 = c1[3 * i], g1 = c1[3 * i + 1], b1 = c1[3 * i + 2];
        float dr = c2[3 * i] - r1, dg = c2[3 * i + 1] - g1, db = c2[3 * i + 2] - b1;
        float hsc = o * hs[i] * wid[i] * 0.5f;
        float ulo = (0.0f - cmx) / isx, uhi = (mw - 1.001f - cmx) / isx;
        float vlo = (0.0f - cmy) / isy, vhi = (mh - 1.001f - cmy) / isy;
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
                if (u < 0.0f || v < 0.0f || u >= mw - 1.001f || v >= mh - 1.001f) continue;
                int iu = (int)u, iv = (int)v;
                float fu = u - iu, fv = v - iv;
                const float *p00 = m + ((long)iv * mw + iu) * 3;
                const float *p01 = p00 + 3, *p10 = p00 + (long)mw * 3, *p11 = p10 + 3;
                float w00 = (1 - fu) * (1 - fv), w01 = fu * (1 - fv), w10 = (1 - fu) * fv, w11 = fu * fv;
                float a = p00[0] * w00 + p01[0] * w01 + p10[0] * w10 + p11[0] * w11;
                if (a < 0.002f) continue;
                /* the plane's depth here, kept within [0.75, 2] times the stroke's own (grazing planes) */
                float iz = fminf(fmaxf(iz0 + gx * dx + gy * dy, izlo), izhi), zt = 1.0f / iz;
                float vis = (dmax[(long)py * W + px] - zt) / (0.005f + 0.005f * zt) + 2.0f;
                if (vis <= 0.0f) continue;
                if (vis < 1.0f) a *= vis;
                float st = p00[1] * w00 + p01[1] * w01 + p10[1] * w10 + p11[1] * w11;
                float he = p00[2] * w00 + p01[2] * w01 + p10[2] * w10 + p11[2] * w11;
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

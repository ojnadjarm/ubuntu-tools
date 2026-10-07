/* Procedural agent creatures: the same id always draws the same SVG creature. */
const KATA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ";
const HUES = [152, 172, 192, 118, 44, 24, 268, 318, 206, 88];

function hash(s) { let h = 2166136261; for (const ch of s) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
function rng(seed) { let a = seed; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const pick = (r, a) => a[(r() * a.length) | 0];
const f = (n) => n.toFixed(1);

/* Closed Catmull-Rom through the points, as cubic Beziers. */
function smooth(p) {
  let d = `M${f(p[0][0])} ${f(p[0][1])}`;
  for (let i = 0; i < p.length; i++) {
    const a = p[(i - 1 + p.length) % p.length], b = p[i], c = p[(i + 1) % p.length], e = p[(i + 2) % p.length];
    d += `C${f(b[0] + (c[0] - a[0]) / 6)} ${f(b[1] + (c[1] - a[1]) / 6)} ${f(c[0] - (e[0] - b[0]) / 6)} ${f(c[1] - (e[1] - b[1]) / 6)} ${f(c[0])} ${f(c[1])}`;
  }
  return d + "Z";
}

/* The genome of agent `id`: the same id always gives the same body, eyes, topper, mouth and marks; the 3D creatures and the SVG read it. */
export function params(id) {
  const r = rng(hash(id)), h = pick(r, HUES);
  const W = 0.9 + r() * 0.25, Hh = 0.85 + r() * 0.25, lobes = 3 + ((r() * 4) | 0), wob = 0.03 + r() * 0.05, ph = r() * 6.28, sq = 2.2 + r() * 1.6;
  const eyes = pick(r, [1, 2, 2, 2, 3]), gi = hash(id + "g") % KATA.length, topper = pick(r, ["ant", "ant", "ears", "horns", "sprout", "none"]), mouth = pick(r, ["smile", "cat", "o", "fang"]);
  const spots = r() < 0.55, ant = topper === "ant" ? [r(), r(), r(), r()] : [], dots = spots ? Array.from({ length: 12 }, () => r()) : [];
  return { h, W, Hh, lobes, wob, ph, sq, eyes, gi, glyph: KATA[gi], topper, mouth, spots, ant, dots, seed: (hash(id + "s") % 1000) / 1000 };
}

/* SVG string for agent `id` in state working|done|error|stale|sleep. */
export function creature(id, state = "working") {
  const P = params(id), { h, W, Hh, lobes, wob, ph, sq, eyes, glyph, topper, mouth, spots } = P, uid = "c" + hash(id).toString(36);
  let ai = 0, di = 0;
  const ra = () => P.ant[ai++], rd = () => P.dots[di++];
  const pts = [];
  for (let i = 0; i < 28; i++) {
    const a = (i / 28) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
    const k = 1 / Math.pow(Math.pow(Math.abs(c), sq) + Math.pow(Math.abs(s), sq), 1 / sq);
    const rr = 34 * k * (1 + wob * Math.sin(lobes * a + ph)) * (s > 0 ? 1.04 : 0.96);
    pts.push([50 + c * rr * W, 56 + s * rr * Hh]);
  }
  const top = 56 - 34 * Hh, es = eyes === 1 ? 13 : eyes === 2 ? 9.5 : 7.5, ey = 50 - (eyes === 1 ? 2 : 0);
  const ex = eyes === 1 ? [50] : eyes === 2 ? [50 - 13 * W, 50 + 13 * W] : [50 - 17 * W, 50, 50 + 17 * W];
  const fill = `hsl(${h} 72% 60%)`, deep = `hsl(${h} 62% 34%)`, lite = `hsl(${h} 90% 82%)`;
  const shut = state === "done" || state === "sleep" || state === "stale", worry = state === "error";
  let s = `<svg viewBox="0 0 100 100" class="cr ${state}" role="img" aria-hidden="true"><defs><radialGradient id="${uid}" cx="38%" cy="30%" r="80%"><stop offset="0" stop-color="${lite}"/><stop offset=".45" stop-color="${fill}"/><stop offset="1" stop-color="${deep}"/></radialGradient><clipPath id="${uid}k"><path d="${smooth(pts)}"/></clipPath></defs>`;
  if (topper === "ant") [-1, 1].forEach((d) => { const x = 50 + d * 11 * W, tx = 50 + d * (18 + ra() * 8), ty = top - 12 - ra() * 6; s += `<path d="M${f(x)} ${f(top + 4)}Q${f(x + d * 2)} ${f(ty + 6)} ${f(tx)} ${f(ty)}" stroke="${deep}" stroke-width="2.4" fill="none" stroke-linecap="round"/><circle cx="${f(tx)}" cy="${f(ty)}" r="4" fill="#eafff2" class="tip"/>`; });
  if (topper === "ears") [-1, 1].forEach((d) => { s += `<path d="M${f(50 + d * 12 * W)} ${f(top + 8)}L${f(50 + d * 26 * W)} ${f(top - 10)}L${f(50 + d * 28 * W)} ${f(top + 14)}Z" fill="${deep}"/>`; });
  if (topper === "horns") [-1, 1].forEach((d) => { s += `<path d="M${f(50 + d * 14 * W)} ${f(top + 6)}q${f(d * 4)} -14 ${f(d * 12)} -16q${f(-d * 3)} 8 ${f(-d * 4)} 18Z" fill="#ffd166" opacity=".9"/>`; });
  if (topper === "sprout") s += `<path d="M50 ${f(top + 3)}v-9" stroke="${deep}" stroke-width="2.4"/><path d="M50 ${f(top - 5)}c-9 -2 -13 -9 -11 -12c6 0 11 4 11 12zM50 ${f(top - 5)}c7 -2 11 -8 10 -11c-6 0 -10 4 -10 11z" fill="#4dffa0"/>`;
  s += `<ellipse cx="${f(50 - 14 * W)}" cy="92" rx="8" ry="4" fill="${deep}"/><ellipse cx="${f(50 + 14 * W)}" cy="92" rx="8" ry="4" fill="${deep}"/>`;
  s += `<path d="${smooth(pts)}" fill="url(#${uid})"/>`;
  s += `<g clip-path="url(#${uid}k)">`;
  if (spots) for (let i = 0; i < 4; i++) s += `<circle cx="${f(22 + rd() * 56)}" cy="${f(62 + rd() * 26)}" r="${f(3 + rd() * 5)}" fill="${lite}" opacity=".35"/>`;
  s += `<ellipse cx="50" cy="${f(56 + 30 * Hh)}" rx="${f(20 * W)}" ry="12" fill="${lite}" opacity=".28"/><text x="50" y="${f(56 + 26 * Hh)}" font-size="11" text-anchor="middle" fill="${deep}" opacity=".7">${glyph}</text></g>`;
  ex.forEach((x) => {
    if (shut) s += `<path d="M${f(x - es * 0.8)} ${f(ey)}q${f(es * 0.8)} ${state === "stale" ? 0 : -es * 0.7} ${f(es * 1.6)} 0" stroke="#04140c" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
    else s += `<g class="lid" style="transform-origin:${f(x)}px ${f(ey)}px"><circle cx="${f(x)}" cy="${f(ey)}" r="${f(es)}" fill="#f4fff8"/><circle cx="${f(x + es * 0.12)}" cy="${f(ey + es * 0.15)}" r="${f(es * 0.62)}" fill="#04140c"/><circle cx="${f(x + es * 0.34)}" cy="${f(ey - es * 0.2)}" r="${f(es * 0.24)}" fill="#fff"/><circle cx="${f(x - es * 0.12)}" cy="${f(ey + es * 0.4)}" r="${f(es * 0.1)}" fill="#fff"/></g>`;
    if (worry) s += `<path d="M${f(x - es)} ${f(ey - es * 1.25)}l${f(es * 1.6)} ${f(es * 0.45)}" stroke="#04140c" stroke-width="2.4" stroke-linecap="round"/>`;
  });
  const my = ey + es + 10;
  s += `<ellipse cx="${f(50 - 22 * W)}" cy="${f(my - 3)}" rx="5" ry="3" fill="#ff9ec4" opacity=".45"/><ellipse cx="${f(50 + 22 * W)}" cy="${f(my - 3)}" rx="5" ry="3" fill="#ff9ec4" opacity=".45"/>`;
  if (worry) s += `<path d="M44 ${f(my + 3)}q6 -6 12 0" stroke="#04140c" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
  else if (mouth === "smile" || shut) s += `<path d="M44 ${f(my)}q6 6 12 0" stroke="#04140c" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
  else if (mouth === "cat") s += `<path d="M43 ${f(my)}q3.5 4 7 0q3.5 4 7 0" stroke="#04140c" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  else if (mouth === "o") s += `<ellipse cx="50" cy="${f(my + 1)}" rx="3.4" ry="4" fill="#04140c"/>`;
  else s += `<path d="M44 ${f(my)}q6 6 12 0" stroke="#04140c" stroke-width="2.4" fill="none" stroke-linecap="round"/><path d="M53 ${f(my + 1.5)}l1.6 3.4l1.6 -3.9z" fill="#fff"/>`;
  if (state === "stale") s += `<text x="74" y="${f(top + 4)}" font-size="12" fill="#83a08f">z</text><text x="82" y="${f(top - 6)}" font-size="9" fill="#6a8a7a">z</text>`;
  return s + "</svg>";
}

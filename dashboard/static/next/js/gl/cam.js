/* The eye camera in JS, the same maths as EYECAM in the shaders: projection of eye-space points, ring planes and the fit of an eye into a box. */
export const D = 7, K = D / Math.sqrt(D * D - 1);
export const FACE = [0, 0.3, 0.954], ORBIT = [0, 0.74, 0.6726], HALO = [0, 0.9536, 0.3011];

/* Rotation of the eye camera for cam = [yaw, pitch], the product camRot() builds in the shader; rows of a 3×3. */
export function camRot([yaw, pitch]) {
  const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
  return [[cy, -sy * sp, sy * cp], [0, cp, sp], [-sy, -cy * sp, cy * cp]];
}

/* Screen position (CSS px) of eye-space point p for an eye at (x, y) with radius r px; z = distance along the view axis, s = px per eye unit there. */
export function project(p, eye, cam = [0, 0]) {
  const M = camRot(cam), o = [M[0][2] * D, M[1][2] * D, M[2][2] * D], d = [p[0] - o[0], p[1] - o[1], p[2] - o[2]];
  const c = [M[0][0] * d[0] + M[1][0] * d[1] + M[2][0] * d[2], M[0][1] * d[0] + M[1][1] * d[1] + M[2][1] * d[2], M[0][2] * d[0] + M[1][2] * d[1] + M[2][2] * d[2]];
  const z = -c[2], s = D / (Math.max(0.05, z) * K);
  return { x: eye.x + c[0] * s * eye.r, y: eye.y - c[1] * s * eye.r, z, s: s * eye.r };
}

/* In-plane axes of a ring plane with normal n, as the shader builds them: turn 0 at the top, clockwise. */
export function ringAxes(n) {
  const x0 = n[1] + 1e-5, y0 = -n[0], l = Math.hypot(x0, y0), ax = [x0 / l, y0 / l, 0];
  return { ax, ay: [n[1] * ax[2] - n[2] * ax[1], n[2] * ax[0] - n[0] * ax[2], n[0] * ax[1] - n[1] * ax[0]] };
}
/* Eye-space point at turn a on the ring of radius rad. */
export function ringPoint(rad, a, n) {
  const { ax, ay } = ringAxes(n), th = Math.PI / 2 - a * Math.PI * 2, c = Math.cos(th) * rad, s = Math.sin(th) * rad;
  return [ax[0] * c + ay[0] * s, ax[1] * c + ay[1] * s, ax[2] * c + ay[2] * s];
}

/* Centre and radius (px) that fit the eye, its halo and its rings out to `outer` inside box b (a DOMRect), `lift` extra room above in eye units. */
export function fitEye(b, { outer = 0, n = FACE, halo = false, pad = 0.04, lift = 0, cap = Infinity } = {}) {
  const O = { x: 0, y: 0, r: 1 };
  let L = 1.06, R = 1.06, U = 1.06 + lift, Dn = 1.06;
  const edge = (p) => { L = Math.max(L, -p.x); R = Math.max(R, p.x); U = Math.max(U, -p.y + lift); Dn = Math.max(Dn, p.y); };
  if (halo) for (let j = 0; j < 32; j++) edge(project(ringPoint(1.63, j / 32, HALO), O));
  if (outer > 0) for (let j = 0; j < 48; j++) edge(project(ringPoint(outer + 0.08, j / 48, n), O));
  const r = Math.max(4, Math.min(cap, (Math.min(b.width / (L + R), b.height / (U + Dn))) * (1 - pad)));
  return { x: b.left + b.width / 2 - ((R - L) / 2) * r, y: b.top + b.height / 2 - ((Dn - U) / 2) * r, r };
}

/* The furniture kit (66 models, Kenney Furniture Kit 2.0, CC0): fetched once, on first use, and decoded to typed arrays. */
const bytes = (s, T) => { const bin = atob(s), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return new T(u.buffer); };
export function decode(kit) {
  const models = {};
  for (const [k, m] of Object.entries(kit.models)) models[k] = { p: bytes(m.p, Float32Array), n: bytes(m.n, Int8Array), m: bytes(m.m, Uint8Array), i: bytes(m.i, Uint16Array), s: m.s };
  return { mats: kit.mats, models };
}
let kit;
/* The decoded kit; every caller shares one fetch. */
export const load = () => (kit ??= fetch("/static/next/office/kit.json").then((r) => r.json()).then(decode));

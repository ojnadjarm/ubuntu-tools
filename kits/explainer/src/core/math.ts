/** Small numeric helpers shared by every module. */
export const clamp = (x: number, a = 0, b = 1): number => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, t: number): number => a + (b - a) * t;
export const smooth = (x: number): number => { const t = clamp(x); return t * t * (3 - 2 * t); };
export const damp = (a: number, b: number, rate: number, dt: number): number => lerp(a, b, 1 - Math.exp(-rate * dt));

/** Deterministic PRNG (mulberry32). */
export function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => { s = (s + 0x6d2b79f5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
/** The numeric fields of a state object (GSAP adds a circular `_gsap`; this copy is safe to keep, compare and serialise). */
export const numbers = <S extends object>(s: S): S => Object.fromEntries(Object.entries(s).filter(([, v]) => typeof v === 'number')) as S;

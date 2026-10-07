/** The number rules of the plate: a true minus sign (U+2212), the shortest exact form up to two decimals, negative operands bracketed. */
export const MINUS = '−';

/** A value in its shortest exact form: 2, 2.5, 0.25, −1. */
export function num(v: number): string {
  const r = Math.round(v * 100) / 100;
  return (r < 0 ? MINUS : '') + String(Math.abs(r));
}

/** A dial setting, always signed: +1, −0.5, 0. */
export const signed = (v: number): string => (Math.round(v * 100) === 0 ? '0' : (v > 0 ? '+' : '') + num(v));

/** A value inside a sum or product: bracketed when negative, so 2 × (−1) never reads as a subtraction. */
export const op = (v: number): string => (Math.round(v * 100) < 0 ? `(${num(v)})` : num(v));

/** One product, worked: 2 × 0.5 = 1. */
export const product = (x: number, w: number): string => `${op(x)} × ${op(w)} = ${num(x * w)}`;

/** A sum of terms, worked: 1 + (−1) = 0. */
export const sum = (terms: number[]): string => `${terms.map(op).join(' + ')} = ${num(terms.reduce((a, b) => a + b, 0))}`;

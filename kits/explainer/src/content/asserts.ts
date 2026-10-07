/** Neutral sentence asserts: names, `prev.<name>`, numbers, comparisons, + − * /, parentheses, abs(), round(), and / or / not. */
type Env = Record<string, number>;
type Node = (now: Env, prev: Env) => number;

const TOKEN = /\s*(prev\.[A-Za-z_]\w*|[A-Za-z_]\w*|\d+(?:\.\d+)?|==|!=|<=|>=|[<>+\-−*/(),])/y;
const EPS = 1e-9;
const FN: Record<string, (x: number) => number> = { abs: Math.abs, round: Math.round };
const CMP: Record<string, (a: number, b: number) => boolean> = {
  '==': (a, b) => Math.abs(a - b) < EPS, '!=': (a, b) => Math.abs(a - b) >= EPS,
  '<': (a, b) => a < b - EPS, '<=': (a, b) => a <= b + EPS, '>': (a, b) => a > b + EPS, '>=': (a, b) => a >= b - EPS,
};

function tokens(src: string): string[] {
  const out: string[] = [];
  TOKEN.lastIndex = 0;
  while (TOKEN.lastIndex < src.length) {
    const at = TOKEN.lastIndex, m = TOKEN.exec(src);
    if (!m) { if (src.slice(at).trim() === '') break; throw new Error(`assert "${src}": cannot read "${src.slice(at).trim()}"`); }
    out.push(m[1] === '−' ? '-' : m[1]);
  }
  return out;
}

const lookup = (env: Env, name: string, src: string): number => {
  if (!(name in env)) throw new Error(`assert "${src}": no value ${name}`);
  return env[name];
};

/** Parse an assert into a predicate over (state now, state before the last change); throws on anything outside the grammar. */
export function parseAssert(src: string): (now: Env, prev?: Env) => boolean {
  const t = tokens(src);
  let i = 0;
  const peek = (): string | undefined => t[i];
  const eat = (x: string): void => { if (t[i] !== x) throw new Error(`assert "${src}": expected ${x} at ${t[i] ?? 'the end'}`); i++; };
  const or = (): Node => { let a = and(); while (peek() === 'or') { i++; const l = a, r = and(); a = (n, p) => +(!!l(n, p) || !!r(n, p)); } return a; };
  const and = (): Node => { let a = not(); while (peek() === 'and') { i++; const l = a, r = not(); a = (n, p) => +(!!l(n, p) && !!r(n, p)); } return a; };
  const not = (): Node => { if (peek() === 'not') { i++; const x = not(); return (n, p) => +!x(n, p); } return cmp(); };
  const cmp = (): Node => {
    const a = sum(), op = peek();
    if (!op || !CMP[op]) return a;
    i++;
    const b = sum(), f = CMP[op];
    return (n, p) => +f(a(n, p), b(n, p));
  };
  const sum = (): Node => {
    let a = prod();
    while (peek() === '+' || peek() === '-') { const op = t[i++], l = a, r = prod(); a = op === '+' ? (n, p) => l(n, p) + r(n, p) : (n, p) => l(n, p) - r(n, p); }
    return a;
  };
  const prod = (): Node => {
    let a = unary();
    while (peek() === '*' || peek() === '/') { const op = t[i++], l = a, r = unary(); a = op === '*' ? (n, p) => l(n, p) * r(n, p) : (n, p) => l(n, p) / r(n, p); }
    return a;
  };
  const unary = (): Node => { if (peek() === '-') { i++; const x = unary(); return (n, p) => -x(n, p); } return atom(); };
  const atom = (): Node => {
    const x = t[i++];
    if (x === undefined) throw new Error(`assert "${src}": ends early`);
    if (x === '(') { const e = or(); eat(')'); return e; }
    if (/^\d/.test(x)) { const v = Number(x); return () => v; }
    if (FN[x]) { eat('('); const e = or(); eat(')'); const f = FN[x]; return (n, p) => f(e(n, p)); }
    if (x.startsWith('prev.')) { const k = x.slice(5); return (_, p) => lookup(p, k, src); }
    if (/^[A-Za-z_]/.test(x) && !['and', 'or', 'not'].includes(x)) return (n) => lookup(n, x, src);
    throw new Error(`assert "${src}": unexpected ${x}`);
  };
  const root = or();
  if (i < t.length) throw new Error(`assert "${src}": unexpected ${t[i]}`);
  return (now, prev = {}) => !!root(now, prev);
}

/** Evaluate one assert against the named numbers now and before the last change. */
export const evalAssert = (src: string, now: Env, prev: Env = {}): boolean => parseAssert(src)(now, prev);

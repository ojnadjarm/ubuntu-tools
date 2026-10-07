/** Progress of one unit; `state` only ever moves forward (seen → driven → played → cleared). */
export interface UnitProgress {
  state?: string; beat?: string; t?: number; furthest?: number; snap?: unknown;
  terms?: string[]; done?: string[]; visited?: string[]; firstAt?: number; lastAt?: number;
}
/** Learner preferences: captions, voice and effects volume (0–1), mute. */
export interface Prefs { cc?: boolean; voice?: number; sfx?: number; muted?: boolean }
/** The one stored value, `plates:v1:progress`. */
export interface Saved { v: 1; units: Record<string, UnitProgress>; resume?: { unit: string; beat: string; t?: number }; missed?: Record<string, number>; prefs?: Prefs }
/** Where the JSON lives; either call may throw. */
export interface Storage { read(): string | null; write(v: string): void }

export const PROGRESS_KEY = 'plates:v1:progress';
const ORDER = ['seen', 'driven', 'played', 'cleared'];
/** Lists that only grow: a save never forgets a term named, a beat entered or a beat done. */
const SETS = ['terms', 'done', 'visited'] as const;
const union = (a: string[] = [], b: string[] = []): string[] => [...new Set([...a, ...b])];

/** In-memory storage: tests, private windows, blocked storage. */
export class MemoryStorage implements Storage {
  private v: string | null;
  constructor(v: string | null = null) { this.v = v; }
  read(): string | null { return this.v; }
  write(v: string): void { this.v = v; }
}
/** Browser localStorage under one key. */
export class LocalStorage implements Storage {
  private key: string;
  constructor(key = PROGRESS_KEY) { this.key = key; }
  read(): string | null { return localStorage.getItem(this.key); }
  write(v: string): void { localStorage.setItem(this.key, v); }
}

/** Repository over the stored progress: every call fails soft to memory, and older or broken values migrate to `v: 1`. */
export class LearnerStore {
  private storage: Storage;
  private data: Saved;
  constructor(storage: Storage = new MemoryStorage()) {
    this.storage = storage;
    let raw: string | null = null;
    try { raw = storage.read(); } catch { this.storage = new MemoryStorage(); }
    let parsed: unknown = null;
    try { parsed = raw ? JSON.parse(raw) : null; } catch { parsed = null; }
    this.data = LearnerStore.migrate(parsed);
  }
  /** Any stored value → a valid `Saved` (unknown fields kept, broken ones dropped). */
  static migrate(x: unknown): Saved {
    const o = x && typeof x === 'object' ? (x as Record<string, unknown>) : {};
    const units = o.units && typeof o.units === 'object' ? (o.units as Record<string, UnitProgress>) : {};
    return { ...o, v: 1, units } as Saved;
  }
  get(): Saved { return this.data; }
  unit(id: string): UnitProgress { return this.data.units[id] ?? {}; }
  prefs(): Prefs { return this.data.prefs ?? {}; }
  /** Merge `patch` into unit `id`: keep the furthest state and second, grow the sets, and point `resume` at it. */
  save(id: string, patch: UnitProgress): void {
    const cur = this.unit(id), now = Date.now();
    const state = ORDER.indexOf(patch.state ?? '') > ORDER.indexOf(cur.state ?? '') ? patch.state : cur.state ?? 'seen';
    const next: UnitProgress = { ...cur, ...patch, state, firstAt: cur.firstAt ?? now, lastAt: now };
    next.furthest = Math.max(cur.furthest ?? 0, patch.furthest ?? 0);
    for (const k of SETS) if (cur[k] || patch[k]) next[k] = union(cur[k], patch[k]);
    this.data.units[id] = next;
    if (next.beat) this.data.resume = { unit: id, beat: next.beat, t: next.t };
    this.flush();
  }
  setPrefs(p: Prefs): void { this.data.prefs = { ...this.prefs(), ...p }; this.flush(); }
  private flush(): void {
    try { this.storage.write(JSON.stringify(this.data)); } catch { this.storage = new MemoryStorage(JSON.stringify(this.data)); }
  }
}

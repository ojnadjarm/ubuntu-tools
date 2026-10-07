/** Progress the engine reports; the site stores it (localStorage), tests assert on it. */
export type Progress =
  | { type: 'beat'; name: string }
  | { type: 'step'; beat: string; index: number; phase: 'start' | 'done' }
  | { type: 'hint'; beat: string; index: number }
  | { type: 'attempt'; beat: string; index: number; pass: boolean; tries: number }
  | { type: 'detect'; beat: string; task: string; m: string }
  | { type: 'giveup'; beat: string; index: number }
  | { type: 'complete'; beat: string }
  | { type: 'seek'; from: number; to: number }
  | { type: 'span'; index: number; t: number }
  | { type: 'term'; id: string }
  | { type: 'stop'; chapter: string };

type Of<K extends Progress['type']> = Extract<Progress, { type: K }>;

/** Typed publish/subscribe (Observer); `on` returns the unsubscribe. */
export class Events {
  private map = new Map<string, Set<(e: Progress) => void>>();
  log: Progress[] = [];
  on<K extends Progress['type'] | '*'>(type: K, f: (e: K extends Progress['type'] ? Of<K> : Progress) => void): () => void {
    const set = this.map.get(type) ?? new Set();
    set.add(f as (e: Progress) => void); this.map.set(type, set);
    return () => set.delete(f as (e: Progress) => void);
  }
  emit(e: Progress): void {
    this.log.push(e);
    this.map.get(e.type)?.forEach((f) => f(e));
    this.map.get('*')?.forEach((f) => f(e));
  }
}

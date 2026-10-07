/** The Workbench policy numbers: refutations per misconception, firings before a contrast pair, clean first tries before the skip. */
export interface FlowRules { refuteMax: number; contrastAfter: number; skipAfter: number }
export const FLOW: FlowRules = { refuteMax: 2, contrastAfter: 2, skipAfter: 3 };

/** What one detector firing asks for: its refutation now, its contrast pair next. */
export interface Firing { refute: boolean; contrast: boolean }
interface FlowSnap { fired: Record<string, number>; clean: number; offered: boolean }

/** The Workbench flow (pure policy): refute at most twice per misconception, a contrast pair once after two firings, the skip offer once after three clean first tries in a row. */
export class BenchFlow {
  private fired: Record<string, number> = {};
  private clean = 0;
  private offered = false;
  readonly rules: FlowRules;
  constructor(rules: FlowRules = FLOW) { this.rules = rules; }
  fire(m: string): Firing {
    const n = (this.fired[m] = (this.fired[m] ?? 0) + 1);
    return { refute: n <= this.rules.refuteMax, contrast: n === this.rules.contrastAfter };
  }
  count(m: string): number { return this.fired[m] ?? 0; }
  /** A case ended: `clean` is a pass on the first try with no hint; true when the skip is to be offered now. */
  result(clean: boolean): boolean {
    this.clean = clean ? this.clean + 1 : 0;
    if (this.offered || this.clean < this.rules.skipAfter) return false;
    this.offered = true;
    return true;
  }
  snapshot(): FlowSnap { return { fired: { ...this.fired }, clean: this.clean, offered: this.offered }; }
  restore(s: FlowSnap): void { this.fired = { ...s.fired }; this.clean = s.clean; this.offered = s.offered; }
}

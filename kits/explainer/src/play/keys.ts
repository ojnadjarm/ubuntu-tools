import type { Hand } from './hand';

/** What the keyboard path needs from the director. */
export interface KeyTarget {
  hands: Hand[]; activeHand: number;
  /** A dial was picked (tap, Up/Down): in a timed beat Left/Right turn it instead of seeking. */
  picked: boolean;
  beats: { touched(): void; cur: { timed?: boolean } | null };
  wake(): void;
}
/** Player actions the keys call; `close` returns whether it closed something (a callout, a sheet). */
export interface KeyActions {
  toggle(): void; back(): void; fwd(): void;
  home?(): void; help?(): void; mute?(): void; cc?(): void; transcript?(): void; hint?(): void;
  /** Press in: a knob, a pencil, Done, a lever (the beat decides what). */
  commit?(): void;
  close?(): boolean;
  /** Zoom the drawing a level in (+1) or out (−1), or back to the whole drawing (0). */
  zoom?(dir: 1 | -1 | 0): void;
}

/** The key table: the `?` sheet lists it, `bindKeys` follows it, `keyHint` quotes the rows with a `hint`. */
export const KEYS: { keys: string[]; does: string; hint?: string }[] = [
  { keys: ['K', 'Space'], does: 'Pause or play', hint: 'Space pauses' },
  { keys: ['J', ',', '←'], does: 'Back one sentence; in your turn, say it again' },
  { keys: ['L', '.', '→'], does: 'Forward one sentence, up to where you have listened' },
  { keys: ['↑', '↓'], does: 'Pick a dial or a part; then ← → turn or move it', hint: '↑↓ pick a dial, ←→ turn it' },
  { keys: ['Enter'], does: 'Press in: the knob, the pencil, Done, the lever' },
  { keys: ['Esc'], does: 'Close a note, a sheet or the end card; put the dial down', hint: 'Esc closes a note' },
  { keys: ['Home'], does: 'Back to the start of the watch' },
  { keys: ['T'], does: 'Transcript' },
  { keys: ['C'], does: 'Captions' },
  { keys: ['H'], does: 'A hint, when there is one' },
  { keys: ['M'], does: 'Mute or unmute' },
  { keys: ['+', '−'], does: 'Zoom the drawing in or out; drag bare paper to move it' },
  { keys: ['0'], does: 'The whole drawing again' },
  { keys: ['?'], does: 'This sheet', hint: '? lists every key' },
];

/** The Begin card's key line, quoted from the key table. */
export const keyHint = (): string => `${KEYS.filter((k) => k.hint).map((k) => k.hint).join(' · ')}.`;

const typing = (t: EventTarget | null): boolean => typeof HTMLElement !== 'undefined' && t instanceof HTMLElement && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
const onButton = (t: EventTarget | null): boolean => typeof HTMLButtonElement !== 'undefined' && t instanceof HTMLButtonElement;

/** One key press; returns whether it was handled. In a timed beat the arrows step by sentence until a dial is picked; in play they turn the lit dial. */
export function pressKey(d: KeyTarget, a: KeyActions, k: string, button = false): boolean {
  const live = d.hands.map((x, i) => (x.enabled ? i : -1)).filter((i) => i >= 0);
  const timed = !!d.beats.cur?.timed, lower = k.toLowerCase();
  if (k === 'Escape') {
    if (!a.close?.() && d.picked) d.picked = false;
  } else if ((k === 'ArrowUp' || k === 'ArrowDown') && live.length) {
    if (timed && !d.picked) { if (!live.includes(d.activeHand)) d.activeHand = live[0]; }
    else if (live.length > 1) d.activeHand = live[(live.indexOf(d.activeHand) + 1) % live.length];
    d.picked = true;
  } else if ((k === 'ArrowRight' || k === 'ArrowLeft') && (!timed || d.picked) && d.hands[d.activeHand]?.enabled) {
    d.beats.touched();
    d.hands[d.activeHand].turn(k === 'ArrowRight' ? 1 : -1);
  } else if (k === 'ArrowLeft' || lower === 'j' || k === ',') a.back();
  else if (k === 'ArrowRight' || lower === 'l' || k === '.') a.fwd();
  else if (lower === 'k' || (k === ' ' && !button)) a.toggle();
  else if (k === 'Enter' && !button && a.commit) a.commit();
  else if (k === 'Home' && a.home) a.home();
  else if (lower === 't' && a.transcript) a.transcript();
  else if (lower === 'c' && a.cc) a.cc();
  else if (lower === 'h' && a.hint) a.hint();
  else if (lower === 'm' && a.mute) a.mute();
  else if (k === '?' && a.help) a.help();
  else if ((k === '+' || k === '=') && a.zoom) a.zoom(1);
  else if ((k === '-' || k === '_') && a.zoom) a.zoom(-1);
  else if (k === '0' && a.zoom) a.zoom(0);
  else return false;
  d.wake();
  return true;
}

/** Keyboard path to every player action and every hands-on action (`pressKey` on each keydown). */
export function bindKeys(d: KeyTarget, a: KeyActions): void {
  addEventListener('keydown', (e) => {
    if (e.altKey || e.ctrlKey || e.metaKey || typing(e.target)) return;
    if (pressKey(d, a, e.key, onButton(e.target))) e.preventDefault();
  });
}

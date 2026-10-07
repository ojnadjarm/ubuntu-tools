/** Inline SVG icons for the player chrome (24 × 24, `fill: currentColor` from the style's CSS). */
const svg = (d: string): string => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;
export const ICON = {
  play: svg('M8 5.5v13l10.5-6.5z'),
  pause: svg('M7 5h3.5v14H7zM13.5 5H17v14h-3.5z'),
  replay: svg('M12 5a7 7 0 1 1-6.6 4.7l1.9.6A5 5 0 1 0 12 7v3L7.5 6 12 2z'),
  back: svg('M6 5h2v14H6zM19 5.5v13L9.5 12z'),
  sound: svg('M4 9h4l5-4v14l-5-4H4zM16 8.5a5 5 0 0 1 0 7l-1.4-1.4a3 3 0 0 0 0-4.2zM18.4 6a8.5 8.5 0 0 1 0 12L17 16.6a6.5 6.5 0 0 0 0-9.2z'),
  muted: svg('M4 9h4l5-4v14l-5-4H4zM15.3 9.7l1.4-1.4 2.3 2.3 2.3-2.3 1.4 1.4-2.3 2.3 2.3 2.3-1.4 1.4-2.3-2.3-2.3 2.3-1.4-1.4 2.3-2.3z'),
  /** A ruled sheet of working: a page with a folded corner and three rows. */
  sheet: svg('M6 3h9l4 4v14H6zM14 4.5V8h3.5zM8.5 11h8v1.6h-8zM8.5 14.2h8v1.6h-8zM8.5 17.4h5v1.6h-5z'),
  /** A drawn arrow pointing back (left), stroked by the style's CSS. */
  left: '<svg class="arrow" viewBox="0 0 22 12" aria-hidden="true"><path d="M21 6H2M7 1 2 6l5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  list: svg('M4 6h2v2H4zM8 6h12v2H8zM4 11h2v2H4zM8 11h12v2H8zM4 16h2v2H4zM8 16h12v2H8z'),
  /** An ink-drawn cross: two pen strokes (the style's CSS gives the stroke). */
  cross: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.5 6.5 17.5 17.5M17.5 6.5 6.5 17.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  close: svg('M6.4 5 12 10.6 17.6 5 19 6.4 13.4 12l5.6 5.6-1.4 1.4-5.6-5.6L6.4 19 5 17.6 10.6 12 5 6.4z'),
};

/** m:ss for a number of seconds. */
export const clock = (t: number): string => { const s = Math.max(0, Math.floor(t)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
/** Escape text for innerHTML. */
export const esc = (x: string): string => x.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

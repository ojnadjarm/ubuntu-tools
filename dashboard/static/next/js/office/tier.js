/* Which parts of a card show at a glance; everything else sits in the card's one closed Details fold. Pure data, runs under node. */

/* Glance rows and parts by label: true always, a RegExp when the value matches; every other label is a detail. */
export const GLANCE = { Now: true, "Next run": /^in /, "Needs you": true, "Sub-agents running": true, "Workers running": true };
/* The Members list of a room is a detail. */
export const ROLL = "detail";

const on = (k, v) => { const g = GLANCE[k]; return g instanceof RegExp ? g.test(v) : g === true; };
/* A row [label, value, tone?] is glance when its label says so or it is a gold line (something is wrong). */
export const glance = ([k, v, tone]) => tone === "bad" || on(k, String(v));
/* A part is glance when its heading says so and it lists something. */
const shown = (x) => on(x.h, "") && x.rows.length + x.chips.length > 0;

/* A card split in two: `top` (first line, glance rows and parts) and `fold` (the other lines, rows, Members, parts). */
export function tiers(c) {
  const lines = c.lines || [], rows = c.rows || [], parts = c.parts || [];
  return { top: { lines: lines.slice(0, 1), rows: rows.filter(glance), parts: parts.filter(shown), roll: ROLL === "glance" },
    fold: { lines: lines.slice(1), rows: rows.filter((r) => !glance(r)), parts: parts.filter((x) => !shown(x)), roll: ROLL !== "glance" } };
}

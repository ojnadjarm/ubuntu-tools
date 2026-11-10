/* Chat's phone list: the newest message seen per channel, its one-line preview and time, and rows ordered by last activity. */
import { p2 } from "/static/js/core/fmt.js";

const last = {};

/* Remembers the newest of rows per channel. */
export function note(rows) {
  for (const m of rows || []) if (m.ch && (!last[m.ch] || m.id > last[m.ch].id)) last[m.ch] = m;
}

/* Remembers each channel's last message from the channel list ({ch, last}), so channels outside Recent have a preview. */
export function seed(channels) {
  note((channels || []).filter((c) => c.last).map((c) => ({ ...c.last, ch: c.ch })));
}

/* The newest message known in channel c; "" is every channel. */
export function lastIn(c) {
  if (c) return last[c] || null;
  return Object.values(last).reduce((a, m) => (!a || m.id > a.id ? m : a), null);
}

/* Channels newest activity first; channels with nothing seen keep their order after them. */
export const byActivity = (list) => list.map((c, i) => [c, lastIn(c.ch), i])
  .sort((a, b) => (b[1] ? b[1].id : -1) - (a[1] ? a[1].id : -1) || a[2] - b[2]).map((x) => x[0]);

/* One line of message m (files: a list or a count): who said it (unless dm), then its text or "attachment". */
export function peek(m, who, dm) {
  const body = m.text || ((Array.isArray(m.files) ? m.files.length : m.files) ? "attachment" : "");
  return (m.kind === "system" ? "" : m.from === "owner" ? "You: " : dm ? "" : who(m.from) + ": ") + body.replace(/\s+/g, " ");
}

/* Time today, "Yesterday", else day and month. */
export function when(m) {
  const d = new Date(m.ts), now = new Date();
  if (d.toDateString() === now.toDateString()) return p2(d.getHours()) + ":" + p2(d.getMinutes());
  if (d.toDateString() === new Date(now - 864e5).toDateString()) return "Yesterday";
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
}

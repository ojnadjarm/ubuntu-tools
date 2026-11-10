/* Chat's last rows per view (a channel id, "" = Recent): at most MAX views, the newest CAP rows each, so a view he has opened paints at once. */
const MAX = 10, CAP = 200, views = new Map();

/* Keeps view's rows (newest CAP; cut rows set more), the view becoming the newest; the oldest view goes past MAX. */
export function keep(view, { msgs, more }) {
  views.delete(view);
  views.set(view, msgs.length > CAP ? { msgs: msgs.slice(-CAP), more: true } : { msgs, more: !!more });
  if (views.size > MAX) views.delete(views.keys().next().value);
}

/* The kept {msgs, more} of view, or null. */
export const take = (view) => views.get(view) || null;

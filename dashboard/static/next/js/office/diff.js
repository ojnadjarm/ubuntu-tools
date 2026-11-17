/* What changed between two office models, as the patch the renderer and the overlay take. */
import { moves } from "./ceo/desk.js";

const rooms = (M) => [M.ceo, ...M.rooms, ...M.staff].filter(Boolean);
const look = (p) => JSON.stringify([p.pose, p.state, p.since, p.name, p.rank, p.room]);

/* What changed from model a to model b: the layout, day or night, rooms by key, people by look, boards, the band line, a ticket's start or stop (`events`). */
export function diff(a, b) {
  const R = rooms(b), people = R.flatMap((r) => r.people);
  if (!a) return { layout: true, night: false, rooms: R.map((r) => r.id), people: people.map((p) => p.id), panels: Object.keys(b.panels), line: true };
  const was = new Map(rooms(a).map((r) => [r.id, r.key])), saw = new Map(rooms(a).flatMap((r) => r.people).map((p) => [p.id, look(p)]));
  return {
    layout: rooms(a).map((r) => r.id).join("\n") !== R.map((r) => r.id).join("\n"),
    night: a.night !== b.night,
    rooms: R.filter((r) => was.get(r.id) !== r.key).map((r) => r.id),
    people: people.filter((p) => saw.get(p.id) !== look(p)).map((p) => p.id),
    panels: Object.keys(b.panels).filter((k) => JSON.stringify(a.panels[k]) !== JSON.stringify(b.panels[k])),
    line: JSON.stringify(a.line) !== JSON.stringify(b.line), ...moves(a, b),
  };
}

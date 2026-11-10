/* Seat helpers shared by Org and Chat: a seat's state from its sessions, its "Name · Rank" title, its direct-message channel. */
const prot = (s) => !("pid" in s);

/* A seat's state from its own sessions: working, idle, yours (a protected session), else asleep (or off for the always-on seat). */
export function seatState(seat, S) {
  const mine = S.filter((s) => s.seat === seat.id);
  if (mine.some(prot)) return "yours";
  if (mine.some((s) => s.state === "working")) return "working";
  if (mine.length) return "idle";
  return seat.wake === "channel" ? "off" : "asleep";
}

/* A seat or worker as "Name · Rank" when the API gives a rank, else its name. */
export const titled = (s) => (s.rank ? s.name + " · " + s.rank : s.name);

/* The owner's direct message with seat `id`, as Chat names it. */
export const dmOf = (id) => "dm-" + ["owner", id].sort().join("--");

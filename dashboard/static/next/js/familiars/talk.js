/* Who is talking: the sender of a new chat message acts "talking" for TALK_MS; the owner and system lines never do. */
const TALK_MS = 2000;
const until = {}, fresh = {}, subs = new Set();
let timer = 0;

/* Whether seat `id` is talking now; with a message id, whether that message is the one being said. */
export const talking = (id, mid) => (mid == null ? until[id] : fresh[mid]) > Date.now();

/* Calls fn when somebody starts or stops talking. */
export const watch = (fn) => { subs.add(fn); };

/* Takes newly arrived messages; their senders talk until TALK_MS from now. */
export function heard(list) {
  const end = Date.now() + TALK_MS, said = list.filter((m) => m.from !== "owner" && m.kind !== "system");
  if (!said.length) return;
  for (const m of said) { until[m.from] = end; fresh[m.id] = end; }
  clearTimeout(timer);
  timer = setTimeout(() => { timer = 0; for (const k in fresh) delete fresh[k]; subs.forEach((f) => f()); }, TALK_MS + 30);
  subs.forEach((f) => f());
}

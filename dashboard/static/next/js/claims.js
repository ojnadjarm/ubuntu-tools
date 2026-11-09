/* Claims board line "<who> · <paths> · <note…>" → { who, note, paths: [{ short, full }] }, one short label per path. */
const MAX = 52;

/* Home as ~, ~/agents/ dropped (the board's relative root), longer than MAX keeps the trailing segments behind "…/". */
export function shortPath(full) {
  const p = full.replace(/^\/home\/[^/]+\//, "~/").replace(/^~\/agents\//, "");
  if (p.length <= MAX) return p;
  const segs = p.replace(/\/$/, "").split("/");
  let tail = segs.pop();
  while (segs.length && tail.length + segs[segs.length - 1].length + 3 <= MAX) tail = segs.pop() + "/" + tail;
  return tail.length + 2 <= MAX ? "…/" + tail : "…" + tail.slice(-(MAX - 1));
}

export function claimRow(line) {
  const [who, paths = "", ...note] = line.split(" · ");
  return { who, note: note.join(" · "), paths: paths.split(/[\s,]+/).filter(Boolean).map((full) => ({ short: shortPath(full), full })) };
}

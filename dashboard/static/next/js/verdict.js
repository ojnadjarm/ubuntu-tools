/* The verdict from /api/status: the server's one `needs` list is the headline count, the list under it and the badge keys. */
export function verdict(D) {
  const needs = ((D && D.verdict) || {}).needs || [], errs = Object.keys((D && D.errors) || {}), n = needs.length;
  return {
    text: errs.length ? "unknown" : n ? n + (n === 1 ? " needs you" : " need you") : "all clear",
    bad: errs.length > 0 || n > 0,
    items: needs.map((x) => (x.kind === "ask" ? "ask: " : "") + x.text).concat(errs.map((k) => k + " collector: " + D.errors[k])),
    keys: needs.map((x) => (x.kind === "ask" ? "ask:" + x.t : "need:" + x.text)),
  };
}

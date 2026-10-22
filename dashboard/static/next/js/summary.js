/* Band summaries: one line over a shared screen, every count taken from the same source as the panel below it. */
import { getJSON } from "/static/js/core/api.js";
import { hhmm } from "/static/js/core/fmt.js";

export const SYS_TIMER = /^(ubuntu-insights-|launchpadlib-|snap\.)/;
export const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");

/* The ~/drop root listing the Files browser shows, read once per status tick; `done` re-renders when it lands or fails. */
let root = null, rootFor = null, rootAt = "", rootBad = false;
function dropRoot(D, done) {
  if (rootFor !== D) {
    rootFor = D;
    const bad = () => { if (rootFor === D) { rootBad = true; done(); } };
    getJSON("/api/ls?p=").then((j) => { if (j.error) return bad(); if (rootFor === D) { root = j; rootAt = hhmm(new Date().toISOString()); rootBad = false; done(); } }, bad);
  }
  return root;
}

export function summary(id, D, done) {
  const units = (D.units || []).filter((u) => u.group !== "desktop"), sites = D.sites || [], timers = D.timers || [];
  const n = (a, f) => a.filter(f).length, sys = n(timers, (t) => SYS_TIMER.test(t.unit));
  if (id === "services") return `${plural(units.length, "unit")} · ${n(units, (u) => u.active === "failed")} failed · ${plural(n(sites, (s) => s.state === "stray"), "stray")} · ${plural(timers.length - sys, "timer")}${sys ? ` + ${sys} system` : ""}`;
  if (id === "sites") return `${plural(sites.length, "site")} · ${n(sites, (s) => s.state === "down")} down · ${plural(n(sites, (s) => s.state === "stray"), "stray")}`;
  if (id === "docs") return `${plural((D.plans || []).length, "doc")}, newest first`;
  if (id === "files") { const r = dropRoot(D, done); return r ? `${plural(r.count, "item")} in the drop${rootBad ? ` · as of ${rootAt}` : ""}` : rootBad ? "drop unreadable" : "reading the drop"; }
  if (id === "todo") return `${plural((D.todo || []).length, "step")} only you can take · tap done when finished`;
  return "the design system · tokens and components";
}

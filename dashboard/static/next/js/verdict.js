import { esc } from "../../js/core/fmt.js";

/* The verdict from /api/status: the server's one `needs` list is the headline count, the list under it and the badge keys. */
export function verdict(D) {
  const needs = ((D && D.verdict) || {}).needs || [], errs = Object.keys((D && D.errors) || {}), n = needs.length;
  const keys = needs.map((x) => (x.kind === "ask" ? "ask:" + x.t : x.kind === "todo" ? "todo:" + x.todo : "need:" + x.text));
  return {
    text: errs.length ? "unknown" : n ? n + (n === 1 ? " needs you" : " need you") : "all clear",
    bad: errs.length > 0 || n > 0,
    items: needs.map((x) => (x.kind === "ask" ? "ask: " : x.kind === "todo" ? "to do: " : "") + x.text).concat(errs.map((k) => k + " collector: " + D.errors[k])),
    keys,
    rows: needs.map((x, i) => ({ k: keys[i], t: x.t || "", tag: x.kind === "todo" ? "to do" : x.kind === "ask" ? "ask" : "", head: head(x.text), full: x.text }))
      .concat(errs.map((k) => ({ k: "err:" + k, t: "", tag: "collector", head: head(k + " collector: " + D.errors[k]), full: k + " collector: " + D.errors[k] }))),
  };
}

/* First clause of a need, at most 60 characters, cut on a word. */
export function head(s) {
  const c = String(s || "").split(/\s\(|:\s|\s·\s|;\s|\.\s|\s—\s/)[0].trim();
  if (c.length <= 60) return c;
  const cut = c.slice(0, 59), sp = cut.lastIndexOf(" ");
  return (sp > 30 ? cut.slice(0, sp) : cut) + "…";
}

/* ~/drop paths and the ~/agents reports /report serves (ci-fix notes, REPORT.md, logs); trailing punctuation stays outside. */
const C = "[^\\s\u00b7<>\"'/]", LINKS = new RegExp("(~/drop/[^\\s\u00b7<>\"']*[^\\s\u00b7<>\"'.,;:!?)\\]]"
  + "|~/agents/(?:state/ci-fix/" + C + "+\\.md|log/" + C + "+\\.log|(?!(?:secrets|backups)/)[^\\s\u00b7<>\"'/.]" + C + "*/(?:REPORT\\.md|logs/" + C + "+\\.log)))");
const enc = (s) => s.split("/").map(encodeURIComponent).join("/");
const href = (p) => p.startsWith("~/drop/") ? "/files/" + enc(p.slice(7)) : "/report/agents/" + enc(p.slice(9));

/* Escaped text with each linkable path as a link that opens in a new tab. */
export function linked(s) {
  return String(s || "").split(LINKS).map((p, i) => (i % 2
    ? `<a href="${href(p)}" target="_blank" rel="noopener">${esc(p)}</a>`
    : esc(p))).join("");
}

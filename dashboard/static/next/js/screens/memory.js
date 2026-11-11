/* Library › Memory: the memory store read-only. GET /api/memory is the page index, GET /api/memory/page?p= one page's lines; PRIVATE pages by name only. Tab Network (`#memory?v=net`): memory-net.js. */
import { esc, size, when } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import * as shapes from "../shapes.js";
import { fitEye } from "../gl/cam.js";
import { plural } from "../summary.js";
import * as net from "./memory-net.js";

export const own = true;
const STALE_MS = 20000;
let IDX = null, at = 0, err = "", open = "", view = "";
const PG = {};

if (!document.querySelector('link[href="/static/css/memory.css"]')) { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "/static/css/memory.css"; document.head.appendChild(l); }

const href = (p) => "#memory" + (p ? "?p=" + encodeURIComponent(p) : "");
const repaint = () => { if (cur === "memory") go("memory", true); };
net.bind(repaint);
/* Page and view from a hash query: `v=net` is the Network tab, else `p=` the open page. */
const parse = (q) => { const u = new URLSearchParams(q); view = u.get("v") === "net" ? "net" : ""; open = view ? "" : u.get("p") || ""; };
const known = (p) => ((IDX && IDX.pages) || []).find((r) => r.page === p);

export function read(q) { parse(q); }
export function hash() { return view ? "#memory?v=net" : href(open); }
export function input(e) { net.input(e); }

/* Reads the index when missing or stale and the open page when not read yet; no timer. */
export function enter() {
  if (view) net.enter();
  if (!IDX || Date.now() - at > STALE_MS) {
    at = Date.now();
    getJSON("/api/memory").then((j) => { IDX = j; err = ""; }, (e) => { err = e.message; }).then(repaint);
  }
  if (open && !PG[open]) {
    const p = open;
    PG[p] = { wait: true };
    getJSON("/api/memory/page?p=" + encodeURIComponent(p)).then((j) => { PG[p] = j; }, (e) => { PG[p] = { error: e.message }; }).then(repaint);
  }
}

function show(p) {
  if (p === open && !view) return;
  open = p; view = "";
  history.pushState(null, "", href(p));
  go("memory", true);
  scrollTo(0, 0);
}
addEventListener("hashchange", () => {
  if (cur !== "memory" || !location.hash.startsWith("#memory")) return;
  const i = location.hash.indexOf("?");
  parse(i < 0 ? "" : location.hash.slice(i + 1));
  go("memory", true);
});
export function click(e) {
  const t = e.target.closest("a[data-mv]");
  if (t && !e.metaKey && !e.ctrlKey && !e.shiftKey && e.button === 0) {
    e.preventDefault();
    if (t.dataset.mv !== view) { view = t.dataset.mv; open = ""; history.pushState(null, "", hash()); go("memory", true); }
    return true;
  }
  const a = e.target.closest("a[data-mp]");
  if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return false;
  e.preventDefault();
  show(a.dataset.mp);
  return true;
}

/* Inline marks on escaped text: `code`, the owner's (yy-mm-dd) dates, and a trailing → topic linked when that page is listed. */
function inline(t, dir) {
  let h = esc(t).replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\((\d\d-\d\d-\d\d(?:, ?\d\d-\d\d-\d\d)*)\)/g, '<span class="md">($1)</span>');
  return h.replace(/→\s*([\w./-]+)\s*$/, (m, topic) => {
    const p = dir + "/" + topic + ".md", r = known(p);
    return r && !r.private ? `<a class="mt" href="${esc(href(p))}" data-mp="${esc(p)}">→ ${esc(topic)}</a>` : m;
  });
}

/* A page's lines as escaped blocks: headings, list runs, paragraphs. */
function body(lines, page) {
  const dir = page.slice(0, page.lastIndexOf("/")), out = [];
  let list = [];
  const flush = () => { if (list.length) out.push(`<ul>${list.join("")}</ul>`); list = []; };
  for (const l of lines) {
    const m = /^(#{1,6})\s+(.*)$/.exec(l), li = /^\s*[-*]\s+(.*)$/.exec(l);
    if (li) { list.push(`<li>${inline(li[1], dir)}</li>`); continue; }
    flush();
    if (m) out.push(m[1].length === 1 ? `<h3>${inline(m[2], dir)}</h3>` : `<h4>${inline(m[2], dir)}</h4>`);
    else if (l.trim()) out.push(`<p>${inline(l, dir)}</p>`);
  }
  flush();
  return out.join("");
}

/* One row per folder: pages, bytes and newest change, linked to its card. */
function folders() {
  if (!IDX) return "";
  const F = new Map();
  for (const r of IDX.pages) {
    const k = r.page.slice(0, r.page.lastIndexOf("/")), f = F.get(k) || { n: 0, b: 0, t: 0, card: null };
    f.n++; f.b += r.bytes || 0; f.t = Math.max(f.t, r.mtime || 0);
    if (!r.private && /\/(CORE|DOMAIN)\.md$/.test(r.page)) f.card = r.page;
    F.set(k, f);
  }
  const row = ([k, f]) => `<tr><td class="n">${f.card ? `<a href="${esc(href(f.card))}" data-mp="${esc(f.card)}">${esc(k)}</a>` : esc(k)}</td>` +
    `<td class="p">${f.n}</td><td class="p">${f.b ? size(f.b) : "—"}</td><td class="a">${f.t ? esc(when(f.t)) : "—"}</td></tr>`;
  return `<div class="tw mfold"><table><thead><tr><th>folder</th><th class="p">pages</th><th class="p">size</th><th class="a">changed</th></tr></thead><tbody>${[...F].map(row).join("")}</tbody></table></div>`;
}

function reader() {
  if (!open) return `<article class="pane mread" aria-label="about this page"><h2>read only</h2><div class="mabout">` +
    `<p>Pick a page. This is the fleet's memory as the agents load it; the line numbers are hidden.</p>` +
    `<p>To change a line, edit it in Obsidian on the PC (vault <code>$MEMORY_HOME</code>) or tell an agent: the keeper's next run commits your edit as yours.</p>` +
    `<p>Private pages are listed by name only.</p></div>${folders()}</article>`;
  const d = PG[open] || { wait: true }, r = known(open);
  const meta = d.lines ? `${size(d.bytes)} · ${esc(when(d.mtime))}` : "";
  const text = d.wait ? `<p class="sm">reading…</p>` : d.error ? `<p class="sm bad">${esc(d.error)}</p>`
    : d.lines ? `<div class="mtext">${body(d.lines, open)}</div>` : "";
  return `<article class="pane mread" aria-label="${esc(open)}"><a class="mback" href="#memory" data-mp="">← all pages</a>` +
    `<h2><span class="mpath">${esc(open)}</span><s>${r && r.private ? "private" : meta}</s></h2>${text}</article>`;
}

/* The index grouped by folder: core, then each domain. */
function list() {
  if (!IDX) return `<section class="pane mlist" aria-label="memory pages"><h2>pages</h2><p class="sm">${err ? esc(err) : "reading the store…"}</p></section>`;
  const groups = new Map();
  for (const r of IDX.pages) { const k = r.page.slice(0, r.page.lastIndexOf("/")); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
  const row = (r) => {
    const name = r.page.slice(r.page.lastIndexOf("/") + 1);
    if (r.private) return `<li class="priv"><span class="mrow"><b>${esc(name)}</b><span>private · name only</span></span></li>`;
    return `<li${r.page === open ? ' class="on"' : ""}><a class="mrow" href="${esc(href(r.page))}" data-mp="${esc(r.page)}"${r.page === open ? ' aria-current="page"' : ""}><b>${esc(name)}</b><span>${size(r.bytes)} · ${esc(when(r.mtime))}</span></a></li>`;
  };
  return `<section class="pane mlist" aria-label="memory pages"><h2>pages<s>${IDX.count}</s></h2>` +
    [...groups].map(([k, rs]) => `<div class="mgrp"><h3>${esc(k)}</h3><ul>${rs.map(row).join("")}</ul></div>`).join("") + `</section>`;
}

/* Pages | Network. */
function tabs() {
  const t = (v, name) => `<a class="mtab" href="${v ? "#memory?v=net" : "#memory"}" data-mv="${v}" aria-current="${view === v ? "page" : "false"}">${name}</a>`;
  return `<nav class="mtabs" aria-label="memory views">${t("", "pages")}${t("net", "network")}</nav>`;
}

export function render() {
  const sum = IDX ? `${plural(IDX.count, "page")} · ${IDX.private} private · read only · edit in Obsidian on the PC` : err ? "store unreadable" : "reading the store";
  return `<div class="nxs mem"><section class="band" aria-label="Memory summary"><div class="perch" id="perch" aria-hidden="true"></div>` +
    `<div class="bt"><p class="kin" data-dec>Memory</p><p class="bsum">${esc(sum)}</p></div></section>` +
    tabs() + (view ? net.render() : `<div class="mgrid${open ? " open" : ""}">${list()}${reader()}</div>`) + `</div>`;
}

/* The eye perched on the band over one glyph sheet per page. */
export function scene() {
  const narrow = innerWidth < 820, n = IDX ? IDX.count : 0;
  return { key: String(n), pts: [...shapes.dust(narrow ? 600 : 1500), ...shapes.sheets(n, { cols: narrow ? 3 : 6 })], box: document.getElementById("gl"),
    span: narrow ? 12 : 24, tilt: 0.25, eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

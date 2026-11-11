/* Agents › Vault: every secret the broker knows by name, class, state, age and use; Add and Replace open the broker's own page. */
import { esc, when } from "/static/js/core/fmt.js";
import { getJSON } from "/static/js/core/api.js";
import { cur, go } from "/static/js/core/router.js";
import * as shapes from "../shapes.js";
import { fitEye } from "../gl/cam.js";
import { plural } from "../summary.js";

export const own = true;
const STALE_MS = 15000;
const CLASS = { free: "any agent, logged", ruled: "inside its rules, else it asks", critical: "each use approved" };
const STATE = { sealed: ["ok", "sealed"], file: ["warn", "still a file"], empty: ["idle", "no value"] };
let V = null, at = 0, err = "";

if (!document.querySelector('link[href="/static/css/vault.css"]')) { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "/static/css/vault.css"; document.head.appendChild(l); }

/* Reads /api/secrets when missing or stale; no timer. */
export function enter() {
  if (V && Date.now() - at < STALE_MS) return;
  at = Date.now();
  getJSON("/api/secrets").then((j) => { V = j; err = ""; }, (e) => { err = e.message; }).then(() => { if (cur === "vault") go("vault", true); });
}

const age = (ts) => (ts ? when(ts) : "—");
const by = (w) => esc(w.ticket || w.agent || "no lease") + (w.result && w.result !== "ok" ? ` <i>${esc(w.result)}</i>` : "");

function card(s) {
  const [pc, pt] = STATE[s.state] || STATE.empty;
  const who = s.who.length ? s.who.map(by).join(" · ") : "nobody yet";
  return `<article class="pane vc c-${esc(s.class)}" aria-label="${esc(s.name)}">` +
    `<h2><span class="vn">${esc(s.name)}</span><span class="pill vk ${s.class === "free" ? "ok" : s.class === "critical" ? "warn" : "new"}">${esc(s.class)}</span></h2>` +
    `<p class="vu">${esc(s.used_in || "—")}</p>` +
    `<dl class="vf"><div><dt>state</dt><dd><span class="pill ${pc}">${pt}</span></dd></div>` +
    `<div><dt>${s.state === "sealed" ? "sealed" : "changed"}</dt><dd>${age(s.since)}</dd></div>` +
    `<div><dt>last used</dt><dd>${age(s.last_used)}</dd></div>` +
    `<div><dt>7 days</dt><dd><b>${s.uses_7d}</b> uses${s.refusals_7d ? ` · <b class="bad">${s.refusals_7d}</b> refused` : ""}</dd></div></dl>` +
    `<p class="vw"><span>used by</span> ${who}</p>` +
    `<div class="va"><a class="btn" href="${esc(s.replace)}">${s.state === "sealed" ? "replace" : "seal a value"}</a>` +
    (s.reissue ? `<a class="btn ghost" href="${esc(s.reissue)}" target="_blank" rel="noopener noreferrer">new one ↗</a>` : "") + `</div></article>`;
}

export function render() {
  const list = (V && V.secrets) || [];
  const sealed = list.filter((s) => s.state === "sealed").length, uses = list.reduce((n, s) => n + s.uses_7d, 0);
  const sum = V ? `${plural(list.length, "secret")} · ${sealed} sealed · ${list.length - sealed} not yet · ${plural(uses, "use")} in 7 days · values never shown`
    : err ? "broker not answering" : "reading the vault…";
  const legend = Object.entries(CLASS).map(([k, v]) => `<li class="c-${k}"><b>${k}</b> ${esc(v)}</li>`).join("");
  const body = err && !V ? `<p class="sm pad">broker not answering: ${esc(err)}</p>`
    : V ? `<div class="vgrid">${list.map(card).join("")}</div>` : "";
  return `<div class="nxs vault"><section class="band" aria-label="Vault summary"><div class="perch" id="perch" aria-hidden="true"></div>` +
    `<div class="bt"><p class="kin" data-dec>Vault</p><p class="bsum">${esc(sum)}</p></div></section>` +
    `<div class="vbar"><a class="btn gold" href="${esc((V && V.add) || "/vault/add")}">+ add a secret</a><ul class="vleg" aria-label="classes">${legend}</ul></div>` +
    body + `</div>`;
}

/* The eye perched on the band over one glyph sheet per secret. */
export function scene() {
  const narrow = innerWidth < 820, n = V ? V.secrets.length : 0;
  return { key: String(n), pts: [...shapes.dust(narrow ? 600 : 1500), ...shapes.sheets(n, { cols: narrow ? 3 : 6 })], box: document.getElementById("gl"),
    span: narrow ? 12 : 24, tilt: 0.25, eyeEl: document.getElementById("perch"), eyeFit: (b) => fitEye(b, { halo: true, pad: 0 }), halo: 1 };
}

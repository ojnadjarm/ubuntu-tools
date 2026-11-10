/* Terminal screen: the owner's shell (ttyd behind the tailnet-only https :8476 front) in a frame, plus a full-tab link. */
import {esc} from "/static/js/core/fmt.js";
import {store} from "../store.js";

export const own = true, keep = true;
const PORT = 8476;
if (!document.querySelector('link[href="/static/css/terminal.css"]')) { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "/static/css/terminal.css"; document.head.appendChild(l); }

/* The https front on the tailnet name the panel already serves voice from; null when it is unknown. */
export function url(D) {
  try { return "https://" + new URL(D.voice_url).hostname + ":" + PORT + "/"; } catch (e) { return null; }
}
export function render() {
  const u = url(store.D || {});
  const head = `<section class="band" aria-label="Terminal"><div class="perch" id="perch" aria-hidden="true"></div><div class="bt"><p class="kin" data-dec>Terminal</p>` +
    `<p class="bsum">your shell · tailnet only${u ? ` · <a href="${esc(u)}" target="_blank" rel="noopener">open in its own tab ↗</a>` : ""}</p></div></section>`;
  return `<div class="nxs term">${head}` + (u ? `<iframe class="termf" src="${esc(u)}" title="Terminal" allow="clipboard-read; clipboard-write"></iframe>`
    : `<p class="sm pad">terminal address unknown (no tailnet name)</p>`) + `</div>`;
}

/* Shared take helpers, word diff, alert and status line of the voice and pronunciation pages. */
import {esc} from "../core/fmt.js";
import {getJSON} from "../core/api.js";

export var $ = function (id) { return document.getElementById(id); };
export var LEN = { short: { max: 20000, label: "short · about 5 s" }, long: { max: 90000, label: "long · 30 to 60 s" } };
export var LEADIN = 500;

export function lenOf(p) { return LEN[p && p.len] || LEN.short; }
export function takesOf(S, p) { return (p && S.takes[p.id] || []).slice().sort(function (a, b) { return a.id < b.id ? 1 : -1; }); }
export function wrong(t) { var w = 0, x = 0, said = 0; (t.diff || []).forEach(function (o) { said += o[1].length; if (o[0] !== "eq") { w += o[1].length; x += Math.max(0, o[2].length - o[1].length); } }); return { said: said, wrong: w, extra: x }; }
export function hhmm(iso) { return (iso || "").slice(11, 16); }
export function fmt(ms) { return (ms / 1000).toFixed(1) + " s"; }

export function stats(S) {
  return getJSON("/api/voice/stats").then(function (j) {
    S.stale = !j.takes; if (j.takes) S.takes = j.takes;
    if (S.stale && !S.alert) S.alert = { html: "<b>Take list unavailable.</b> The dashboard server is running old code (no takes in /api/voice/stats). Clips still save; restart agents-dashboard.service and reload to see them.", ok: false };
    S.clips = j.clips; S.seconds = j.seconds; return j; });
}

// pid: the prompt this message belongs to; a message for another prompt is never shown
export function alert(S, render, html, ok, pid) { S.alert = { html: html, ok: !!ok, pid: pid || null }; if (!ok && navigator.vibrate) navigator.vibrate([80, 60, 80]); render(); }

export function paintAlert(S, p) {
  if (S.alert && S.alert.pid && S.alert.pid !== p.id) S.alert = null;
  var al = $("alert"); al.hidden = !S.alert; if (S.alert) { al.className = "alert" + (S.alert.ok ? " ok" : ""); al.innerHTML = S.alert.html + '<button class="dismiss" id="dismiss">dismiss</button>'; }
}

export function paintStatus(S, L, idle) {
  var st = $("stateText"), tm = $("timer"), meter = $("meter");
  if (S.rs === "arming") { st.textContent = S.lead > 0 ? "get ready — speak when the countdown ends" : "opening the microphone…"; tm.textContent = S.lead > 0 ? (S.lead / 1000).toFixed(1) + " s" : ""; meter.style.width = S.lead > 0 ? Math.min(100, (LEADIN - S.lead) / LEADIN * 100) + "%" : "0"; }
  else if (S.rs === "recording") { st.textContent = S.cap ? "at the cap — stopping" : "recording · tap stop when you are done"; tm.textContent = fmt(S.elapsed) + " / " + (L.max / 1000) + " s"; meter.style.width = Math.min(100, S.elapsed / L.max * 100) + "%"; }
  else if (S.rs === "uploading") { var ux = Date.now() - S.tx0; st.textContent = ux > 8000 ? "still sending " + fmt(S.take.ms) + " to the machine — slow link, hold on" : "sending " + fmt(S.take.ms) + " to the machine…"; tm.textContent = S.up + "% · " + fmt(ux); meter.style.width = S.up + "%"; }
  else if (S.rs === "transcribing") { var tx = Date.now() - S.tx0; st.textContent = tx > 8000 ? "sent · still transcribing, the model is slow — hold on" : "sent · listening to what you said…"; tm.textContent = fmt(tx); meter.style.width = "100%"; }
  else { st.textContent = idle; tm.textContent = "cap " + (L.max / 1000) + " s"; meter.style.width = "0"; }
}

/* first: label of the target line; raw: also show the transcript as plain text. */
export function diffHtml(t, first, raw) {
  if (t.transcript == null) return '<div class="cmp"><span class="k">heard</span><p class="mute">the transcriber did not answer — clip kept, no comparison</p></div>';
  var a = "", b = "";
  var W = function (w, c) { return '<span class="w ' + c + '">' + esc(w) + "</span>"; };
  (t.diff || []).forEach(function (o) {
    var op = o[0], x = o[1], y = o[2];
    if (op === "eq") { a += x.map(function (w) { return W(w, "eq"); }).join(" ") + " "; b += y.map(function (w) { return W(w, "eq"); }).join(" ") + " "; }
    else if (op === "del") { a += x.map(function (w) { return W(w, "del"); }).join(" ") + " "; b += W("·", "miss") + " "; }
    else if (op === "ins") { b += y.map(function (w) { return W(w, "ins"); }).join(" ") + " "; }
    else { a += x.map(function (w) { return W(w, "sub"); }).join(" ") + " "; b += y.map(function (w) { return W(w, "ins"); }).join(" ") + " "; }
  });
  return '<div class="cmp"><span class="k">' + first + '</span><p>' + a + '</p></div><div class="cmp"><span class="k">it heard</span><p>' + b + "</p></div>" +
    (raw ? '<div class="cmp"><span class="k">as text</span><p class="raw">' + esc(t.transcript) + "</p></div>" : "");
}

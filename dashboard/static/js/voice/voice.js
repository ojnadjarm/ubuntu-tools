/* Voice prompts page: record each corpus prompt, keep or redo its takes. */
import {esc} from "../core/fmt.js";
import {getJSON, postJSON} from "../core/api.js";
import {$, lenOf, takesOf as takesIn, wrong, hhmm, stats as statsOf, alert as alertOn, paintAlert, paintStatus, diffHtml} from "./common.js";
import {recorder, supported} from "./recorder.js";

// the Voice tab remembers which sub-tab was last open
try { if (localStorage.getItem("voiceSection") === "training") location.replace("/pronunciation"); } catch (e) {}

// S is the whole page state; render() draws all of it. Nothing on screen is written anywhere else.
var S = { P: [], takes: {}, idx: 0, rs: "idle", lead: 0, take: null, alert: null, fresh: null, confirm: null, session: 0, sheet: false, elapsed: 0, up: 0, cap: false, tx0: 0, stale: false };
var R = recorder({ S: S, cur: cur, render: render, alert: alert, stats: stats, saved: saved,
  words: { item: "prompt", line: "the prompt above", refreshing: "refreshing the take list…", list: "the take list" } });
var start = R.start, stop = R.stop;

function cur() { return S.P[S.idx]; }
function takesOf(p) { return takesIn(S, p); }
function grade(t) { if (t.transcript == null) return "none"; var g = wrong(t); return g.wrong || g.extra ? "bad" : "good"; }
function best(p) { var g = null; takesOf(p).forEach(function (t) { var k = grade(t); if (k === "good") g = "good"; else if (k === "bad" && g !== "good") g = "bad"; else if (!g) g = "none"; }); return g; }
function stats() { return statsOf(S); }
function alert(html, ok, pid) { alertOn(S, render, html, ok, pid); }

function save() { try { localStorage.setItem("voiceIdx", String(S.idx)); } catch (e) {} }
function restore() { try { var i = parseInt(localStorage.getItem("voiceIdx"), 10); if (i >= 0 && i < S.P.length) S.idx = i; } catch (e) {} }

function go(i, force) {
  if (S.rs !== "idle" && !force) return false;
  if (i < 0 || i >= S.P.length) return false;
  S.idx = i; S.alert = null; S.confirm = null; S.fresh = null; S.sheet = false; save(); render();
  window.scrollTo(0, 0);
  return true;
}

// ---- rendering ----
function render() {
  var p = cur(); if (!p) return;
  var L = lenOf(p), list = takesOf(p), busy = S.rs !== "idle", b = best(p);
  var card = $("prompt");
  card.className = "prompt " + (p.len === "long" ? "long" : "short") + (b === "good" ? " done" : b === "bad" ? " bad" : "");
  card.dataset.rs = S.rs;
  $("pos").textContent = (S.idx + 1) + " / " + S.P.length;
  $("grp").textContent = p.group;
  $("len").textContent = L.label; $("len").className = "pill " + (p.len === "long" ? "gold" : "dim");
  if ($("say").textContent !== p.text) $("say").textContent = p.text;

  paintStatus(S, L, !list.length ? "not recorded yet · tap record, read it, tap stop" : b === "good" ? "good take on disk · next when you are ready" : b === "bad" ? "no clean take yet · redo or move on" : "recorded, not transcribed");
  paintAlert(S, p);

  $("takeCount").textContent = list.length ? list.length + (list.length === 1 ? " take" : " takes") + " · newest first" : "none yet";
  $("legend").hidden = !list.some(function (t) { return grade(t) === "bad"; });
  $("takeList").innerHTML = list.length ? list.map(function (t, i) { return takeCard(t, list.length - i); }).join("") :
    '<div class="empty">' + (busy ? "your take lands here when it is saved" : "No takes of this prompt yet.<br>Tap <b>record</b>, read the line above, tap <b>stop</b>.<br>It stays here until you say otherwise.") + "</div>";

  var recBtn = $("rec");
  recBtn.className = "rec" + (S.rs === "recording" ? " on" : S.rs === "idle" ? "" : " busy");
  recBtn.disabled = S.rs === "arming" || S.rs === "uploading" || S.rs === "transcribing" || !S.ready;
  recBtn.setAttribute("aria-pressed", S.rs === "recording" ? "true" : "false");
  $("recLabel").textContent = S.rs === "recording" ? "stop" : S.rs === "idle" ? (list.length ? "again" : "record") : S.rs === "arming" ? "mic…" : "wait";
  $("back").disabled = busy || S.idx === 0;
  $("next").disabled = busy || S.idx >= S.P.length - 1;
  $("openSheet").disabled = busy;

  $("sheet").hidden = !S.sheet; if (S.sheet) renderSheet();
}

function takeCard(t, n) {
  var g = grade(t), w = wrong(t), verdict = g === "none" ? '<span class="pill dim">no transcript</span>' : g === "good" ? '<span class="pill">all ' + w.said + " words right</span>" : '<span class="pill gold">' + w.wrong + " of " + w.said + " wrong" + (w.extra ? " · +" + w.extra + " extra" : "") + "</span>";
  var c = S.confirm && S.confirm.id === t.id ? S.confirm : null;
  var foot = c ? '<div class="confirm"><span>' + (c.mode === "redo" ? "Delete take " + n + " and record it again?" : "Delete take " + n + " for good?") + '</span><button class="btn warn" data-act="yes" data-id="' + esc(t.id) + '">' + (c.mode === "redo" ? "yes, delete and record" : "yes, delete") + '</button><button class="btn ghost" data-act="no">keep it</button></div>'
    : '<div class="acts"><button class="btn" data-act="redo" data-id="' + esc(t.id) + '">redo take ' + n + '</button><button class="btn ghost" data-act="del" data-id="' + esc(t.id) + '">delete take ' + n + "</button></div>";
  return '<article class="take ' + g + (S.fresh === t.id ? " fresh" : "") + '" data-id="' + esc(t.id) + '"><header><b>take ' + n + '</b><span class="when">' + esc(hhmm(t.recorded_at)) + " · " + esc(t.seconds) + " s</span>" + verdict + "</header>" + diffHtml(t, "you said", true) + foot + "</article>";
}

function renderSheet() {
  var rec = 0, bad = 0;
  S.P.forEach(function (p) { var b = best(p); if (b) { rec++; if (b !== "good") bad++; } });
  $("sRec").textContent = rec; $("sBad").textContent = bad; $("sTodo").textContent = S.P.length - rec;
  $("sHint").textContent = !rec ? "Nothing recorded yet — " + S.P.length + " prompts waiting. Tap one to start there." : (S.clips || 0) + " clip" + (S.clips === 1 ? "" : "s") + " on disk · " + Math.round(S.seconds || 0) + " s of your speech · " + S.session + " this visit. Tap a prompt to go to it.";
  $("list").innerHTML = S.P.map(function (p, i) {
    var b = best(p), t = takesOf(p), pill = !b ? '<span class="pill dim">to do</span>' : b === "good" ? '<span class="pill">good</span>' : b === "bad" ? '<span class="pill gold">redo</span>' : '<span class="pill vio">no text</span>';
    return '<button class="row ' + (b === "bad" ? "bad" : b ? "ok" : "todo") + (i === S.idx ? " cur" : "") + '" data-i="' + i + '"><span class="n">' + (i + 1) + '</span><span class="t">' + esc(p.text) + "</span>" + pill + "</button>";
  }).join("");
  var c = $("list").querySelector(".cur"); if (c) c.scrollIntoView({ block: "center" });
}

function saved(j, t) {
  var g = grade(j), w = wrong(j);
  var heard = j.transcript == null ? "" : ' It heard <q>' + esc(j.transcript) + "</q>";
  var msg = g === "good" ? "<b>Saved, all " + w.said + " words right.</b>" + heard + " Next when you are ready, or record it again." : g === "bad" ? "<b>Saved.</b> " + w.wrong + " of " + w.said + " words came out wrong." + heard + " The word diff is in take " + takesOf(cur()).length + " below. Redo it, or move on." : "<b>Saved,</b> but the transcriber did not answer, so there is nothing to compare. The clip is kept as take " + takesOf(cur()).length + " below.";
  alert(msg + " Clip " + esc(j.id) + ", " + esc(j.seconds) + " s.", g === "good", t.id);
  stats().then(render, function () { if (!cur() || cur().id !== t.id) return; alert(msg + " (The take list could not refresh from the machine; what you see is this visit only.)", g === "good", t.id); });
}

function del(id, thenRecord) {
  S.confirm = null; render();
  return postJSON("/api/voice/delete", { id: id }).catch(function (e) { if (e.status !== 404) throw e.status ? new Error("HTTP " + e.status) : e; }).then(function () {
    S.session = Math.max(0, S.session - 1);
    return stats();
  }).then(function () { if (thenRecord) start(); else alert("<b>Take " + esc(id) + " deleted.</b>", true); }, function (e) { alert("<b>Could not delete</b> " + esc(id) + ": " + esc(e.message)); });
}

// ---- wiring ----
$("rec").onclick = function () { if (S.rs === "recording") stop(); else if (S.rs === "idle") start(); };
$("back").onclick = function () { go(S.idx - 1); };
$("next").onclick = function () { go(S.idx + 1); };
$("openSheet").onclick = function () { if (S.rs === "idle") { S.sheet = true; render(); } };
$("closeSheet").onclick = function () { S.sheet = false; render(); };
$("list").onclick = function (e) { var b = e.target.closest("button[data-i]"); if (b) go(parseInt(b.dataset.i, 10)); };
$("alert").onclick = function (e) { if (e.target.id === "dismiss") { S.alert = null; render(); } };
$("takeList").onclick = function (e) {
  var b = e.target.closest("button[data-act]"); if (!b || S.rs !== "idle") return;
  var act = b.dataset.act, id = b.dataset.id;
  if (act === "del" || act === "redo") { S.confirm = { id: id, mode: act }; render(); }
  else if (act === "no") { S.confirm = null; render(); }
  else if (act === "yes") del(id, S.confirm && S.confirm.mode === "redo");
};
document.addEventListener("click", function (e) { var a = e.target.closest(".seg a"); if (a) { try { localStorage.setItem("voiceSection", a.dataset.sec); } catch (x) {} } });
document.addEventListener("keydown", function (e) { if (e.key === "Escape" && S.sheet) { S.sheet = false; render(); } });

getJSON("/api/voice/prompts").then(function (j) { S.P = j; return stats(); }).then(function () {
  restore(); S.ready = true; render(); var why = supported(); if (why) alert(why);
}).catch(function (e) { $("say").textContent = "could not load the prompts: " + e; });

// test hook: state and the forced prompt change used by the prompt-integrity test
window.__voice = { state: function () { return S; }, go: go, start: start, stop: stop, setElapsed: function (ms) { if (S.take) S.take.t0 = Date.now() - ms; }, render: render };

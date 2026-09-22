/* Pronunciation page: a linear path of drill steps, each cleared when every target word arrives. */
import {esc} from "../core/fmt.js";
import {getJSON, postJSON} from "../core/api.js";
import {$, lenOf, takesOf as takesIn, hhmm, stats as statsOf, alert as alertOn, paintAlert, paintStatus, diffHtml} from "./common.js";
import {recorder, supported} from "./recorder.js";
import {ask} from "../ui/confirm.js";

var PAT = ["final-consonant", "v-b", "ch-sh", "vowel"];
var PATNAME = { "final-consonant": "word endings", "v-b": "V not B", "ch-sh": "CH not SH", "vowel": "vowel shapes" };
var DEN = { "final-consonant": 29, "v-b": 25, "ch-sh": 24, "vowel": 22 };
var TRIES = 3;
var SHORT = { "final-consonant": "endings", "v-b": "v/b", "ch-sh": "ch/sh", "vowel": "vowels" };

// S is the whole page state; render() draws all of it. Nothing on screen is written anywhere else.
var S = { P: [], takes: {}, cleared: {}, idx: 0, rs: "idle", lead: 0, take: null, alert: null, fresh: null, session: 0, elapsed: 0, up: 0, cap: false, tx0: 0, stale: false, ready: false, revisit: false, takeHtml: "" };
var R = recorder({ S: S, cur: cur, render: render, alert: alert, stats: stats, saved: settle,
  words: { item: "step", line: "the line above", refreshing: "refreshing…", list: "the step" } });
var start = R.start, stop = R.stop;

function cur() { return S.P[S.idx]; }
function takesOf(p) { return takesIn(S, p); }
function stats() { return statsOf(S); }
function alert(html, ok, pid) { alertOn(S, render, html, ok, pid); }

// ---- the path: patterns in order, and inside a pattern the authored day order ----
function difficulty(p) { return [PAT.indexOf(p.pattern), p.day || 0, (p.targets || []).length, p.text.split(/\s+/).length, p.id]; }
function order(list) {
  return list.slice().sort(function (a, b) {
    var x = difficulty(a), y = difficulty(b);
    for (var i = 0; i < x.length; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
    return 0;
  });
}

// ---- what clears a step: every target hit in one take, or across the last three ----
function hitsOf(t) { return (Array.isArray(t.verdict) ? t.verdict : []).filter(function (x) { return x.status === "hit"; }).map(function (x) { return x.word; }); }
function earned(p) {
  var list = takesOf(p).slice(0, TRIES), need = (p.targets || []).map(function (t) { return t.word; });
  if (!need.length || !list.length) return false;
  for (var i = 0; i < list.length; i++) if (hitsOf(list[i]).length === need.length) return true;
  var got = {};
  list.forEach(function (t) { hitsOf(t).forEach(function (w) { got[w] = 1; }); });
  return need.every(function (w) { return got[w]; });
}
// only cleared steps and the step the path is on are reachable; the rest stay locked
function reachable(i) { var p = S.P[i]; return !!p && (i === firstOpen() || !!S.cleared[p.id]); }
function go(i) { if (!reachable(i)) return; S.idx = i; S.revisit = i !== firstOpen(); S.alert = null; S.fresh = null; render(); window.scrollTo(0, 0); }
function firstOpen() { for (var i = 0; i < S.P.length; i++) if (!S.cleared[S.P[i].id]) return i; return S.P.length - 1; }
function clearedCount() { return S.P.filter(function (p) { return S.cleared[p.id]; }).length; }

function progress() {
  return getJSON("/api/voice/progress").then(function (j) { S.cleared = (j && j.cleared) || {}; }, function () {});
}
function markCleared(p) {
  S.cleared[p.id] = new Date().toISOString();
  return postJSON("/api/voice/progress", { cleared: p.id }).then(function (j) { if (j && j.cleared) S.cleared = j.cleared; }, function () {});
}

// ---- per-target verdict: which drill word arrived, and why the red one did not ----
function why(v, pat) {
  var r = v.reason || "", m = /^final (.+) missing$/.exec(r);
  if (m) return "the final “" + m[1] + "” did not arrive";
  if (r === "b for v") return "the v came out as b";
  if (r === "sh for ch") return "the ch came out as sh";
  if (r === "sh for j") return "the j came out as sh";
  if (/^heard as /.test(r)) return pat === "final-consonant" ? "the ending did not arrive" : pat === "v-b" ? "the v came out as b" : pat === "ch-sh" ? "the ch came out as sh" : "the vowel moved";
  return "nothing arrived in its place";
}
// ---- hear it: pre-generated wavs under /tts, one <audio> reused ----
var SND = null;
function slug(w) { return w.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }
function play(file) {
  if (!SND) SND = new Audio();
  SND.pause(); SND.src = "/tts/" + file; SND.play().catch(function () {});
}
function hearBtn(file, label) {
  return '<button class="hear" type="button" data-wav="' + esc(file) + '" aria-label="hear ' + esc(label) + '">&#9654; ' + esc(label) + "</button>";
}

function verdictHtml(t, p) {
  var v = t.verdict;
  if (!Array.isArray(v) || !v.length) return "";
  var hit = v.filter(function (x) { return x.status === "hit"; }).length;
  var miss = v.filter(function (x) { return x.status !== "hit"; }), got = v.filter(function (x) { return x.status === "hit"; });
  var head = miss.length ? '<span class="k gold">replay these ' + miss.length + "</span>" : '<span class="k">' + hit + " of " + v.length + " target words right</span>";
  return '<div class="vd">' + head + miss.concat(got).map(function (x) {
    var ok = x.status === "hit";
    return '<div class="tgt ' + (ok ? "yes" : "no") + '"><i></i><p><b>' + esc(x.word) + "</b>" + hearBtn("w-" + slug(x.word) + ".wav", "say it") +
      (ok ? "" : "<em>" + (x.heard ? "it heard <q>" + esc(x.heard) + "</q> — " : "") + esc(why(x, p && p.pattern)) + "</em>") + "</p></div>";
  }).join("") + (miss.length && got.length ? '<span class="k done">' + hit + " of " + v.length + " already right</span>" : "") + "</div>";
}

// ---- progress: errors per 100 target words, per pattern, newest take of each prompt ----
function renderProg() {
  var acc = {};
  PAT.forEach(function (k) { acc[k] = { miss: 0, seen: 0, prompts: 0 }; });
  S.P.forEach(function (p) {
    var t = takesOf(p)[0], a = acc[p.pattern];
    if (!a || !t || !Array.isArray(t.verdict) || !t.verdict.length) return;
    a.prompts++; a.seen += t.verdict.length;
    a.miss += t.verdict.filter(function (x) { return x.status !== "hit"; }).length;
  });
  var any = PAT.some(function (k) { return acc[k].seen; });
  $("prog").hidden = !any;
  if (!any) return;
  $("progGrid").innerHTML = PAT.map(function (k) {
    var a = acc[k], per = a.seen ? Math.round(a.miss / a.seen * 100) : null;
    return '<div class="cell"><b class="' + (per === null ? "dim" : per > 0 ? "gold" : "") + '">' + (per === null ? "—" : per) + "</b><em>" + PATNAME[k] +
      "</em><s>" + (per === null ? "nothing recorded yet" : (a.seen - a.miss) + " of " + a.seen + " target words right") + "</s></div>";
  }).join("");
  $("progSum").innerHTML = PAT.map(function (k) { var a = acc[k], per = a.seen ? Math.round(a.miss / a.seen * 100) : null; return SHORT[k] + " " + (per === null ? "—" : per > 0 ? "<u>" + per + "</u>" : per); }).join(" · ");
}

// ---- the trail: steps already cleared; tap one to record it again ----
function renderTrail() {
  var done = S.P.map(function (p, i) { return { p: p, i: i }; }).filter(function (x) { return S.cleared[x.p.id]; });
  $("trail").hidden = !done.length;
  if (!done.length) return;
  $("trailCount").textContent = done.length + " of " + S.P.length;
  $("trailRows").innerHTML = done.map(function (x) {
    return '<button class="row ok' + (x.i === S.idx ? " cur" : "") + '" type="button" data-i="' + x.i + '"><span class="n">' + (x.i + 1) + '</span><span class="t">' + esc(x.p.text) + '</span><span class="pill">' + (x.i === S.idx ? "open" : "cleared") + '</span></button>';
  }).join("");
}

// ---- rendering ----
function render() {
  var p = cur(); if (!p) return;
  var L = lenOf(p), list = takesOf(p), busy = S.rs !== "idle", done = !!S.cleared[p.id], tries = list.length;
  var card = $("prompt");
  card.className = "prompt " + (p.len === "long" ? "long" : "short") + (done ? " done" : tries ? " bad" : "");
  card.dataset.rs = S.rs;
  $("pos").textContent = "step " + (S.idx + 1) + " of " + S.P.length;
  $("grp").textContent = PATNAME[p.pattern] || p.pattern;
  $("len").textContent = (p.targets || []).length + " target words"; $("len").className = "pill dim";
  if ($("say").textContent !== p.text) $("say").textContent = p.text;
  $("hearSay").dataset.wav = "s-" + p.id + ".wav";
  $("words").innerHTML = (p.targets || []).map(function (t) { return hearBtn("w-" + slug(t.word) + ".wav", t.word); }).join("");
  $("rule").textContent = S.revisit ? "Cleared step, reopened. Record it again — your place on the path stays at step " + (firstOpen() + 1) + "." :
    done ? "Cleared. Continue opens step " + Math.min(S.P.length, firstOpen() + 1) + "." :
    "This step clears when every marked word arrives — all of them in one take, or across " + TRIES + " takes.";

  paintStatus(S, L, S.revisit ? "reopened · record this step again" : done ? "step cleared · tap continue for the next one" : !tries ? "tap continue, read the line, tap stop" : "not cleared yet · say it again");
  paintAlert(S, p);

  $("takeCount").textContent = tries ? "take " + Math.min(tries, TRIES) + " of " + TRIES : "nothing said yet";
  $("takes").hidden = !list.length;
  $("legend").hidden = !list.length;
  var th = list.slice(0, TRIES).map(function (t, i) { return takeCard(t, list.length - i, i === 0); }).join("");
  if (S.takeHtml !== th) { S.takeHtml = th; $("takeList").innerHTML = th; }
  $("clearBox").innerHTML = !list.length || busy ? "" :
    '<div class="acts clr"><button class="btn ghost" type="button" id="clearAsk">Clear attempts</button></div>';

  var go = $("go");
  go.className = "go" + (S.rs === "recording" ? " on" : busy ? " busy" : done ? " done" : "");
  go.disabled = !S.ready || S.rs === "arming" || S.rs === "uploading" || S.rs === "transcribing";
  $("goLabel").textContent = S.rs === "recording" ? "Stop" : S.revisit ? "Record again" : "Continue";
  $("goSub").textContent = S.rs === "recording" ? "tap when you finished the line" : busy ? "hold on" : S.revisit ? "this cleared step, again" : done ? "next step" : tries ? "say it again" : "record this step";
  $("back").disabled = busy || !reachable(S.idx - 1);
  var rs = $("resume"); rs.hidden = !S.revisit; rs.disabled = busy; rs.innerHTML = "step " + (firstOpen() + 1) + " &rsaquo;";

  renderPath(); renderProg(); renderTrail();
}

function renderPath() {
  $("pbar").innerHTML = S.P.map(function (p, i) { return '<i class="' + (i === S.idx ? "cur" : S.cleared[p.id] ? "ok" : "") + '"></i>'; }).join("");
  var c = $("pathCount"); c.hidden = S.revisit; c.textContent = clearedCount() + " / " + S.P.length; c.title = clearedCount() + " of " + S.P.length + " steps cleared";
}

function takeCard(t, n, open) {
  var hit = (Array.isArray(t.verdict) ? t.verdict : []).filter(function (x) { return x.status === "hit"; }).length;
  var all = (Array.isArray(t.verdict) ? t.verdict : []).length;
  var g = t.transcript == null ? "none" : all && hit === all ? "good" : "bad";
  var pill = g === "none" ? '<span class="pill dim">no transcript</span>' : g === "good" ? '<span class="pill">every target right</span>' : '<span class="pill gold">' + (all - hit) + " of " + all + " missed</span>";
  return '<details class="take ' + g + (S.fresh === t.id ? " fresh" : "") + '" data-id="' + esc(t.id) + '"' + (open ? " open" : "") + '><summary><b>take ' + n + '</b><span class="when">' + esc(hhmm(t.recorded_at)) + " · " + esc(t.seconds) + " s</span>" + pill + "</summary>" + verdictHtml(t, cur()) + diffHtml(t, "the line", false) + "</details>";
}

// ---- the verdict on the step: cleared, or the same step again with the reason ----
function settle(j) {
  var p = cur(), pid = p.id, was = !!S.cleared[pid], v = Array.isArray(j.verdict) ? j.verdict : [], missed = v.filter(function (x) { return x.status !== "hit"; });
  var done = earned(p);
  var msg;
  if (done && was) msg = "<b>Step " + (S.idx + 1) + " again, cleared again.</b> Your place on the path is still step " + (firstOpen() + 1) + ".";
  else if (done) msg = "<b>Step " + (S.idx + 1) + " cleared.</b> Every target word arrived. Tap continue for step " + (S.idx + 2) + ".";
  else if (!v.length) msg = "<b>Saved,</b> but there is nothing to score — the transcriber did not answer. Say it again.";
  else msg = "<b>Step " + (S.idx + 1) + " again.</b> " + missed.length + " of " + v.length + " target words missed: " +
    missed.map(function (x) { return "<q>" + esc(x.word) + "</q> — " + esc(why(x, p.pattern)); }).join("; ") + ".";
  var after = function () { if (!cur() || cur().id !== pid) return; alert(msg, done, pid); };
  if (done && !was) markCleared(p).then(function () { return stats(); }).then(after, after);
  else stats().then(after, after);
}

// ---- clear attempts: only on his tap and one confirm; the server archives the takes ----
function clearAsk() {
  var p = cur(), n = takesOf(p).length;
  return { title: "Clear attempts?", item: n + " takes of step " + (S.idx + 1), body: "They move to the archive and leave this list and the scores; the recordings are kept." + (S.cleared[p.id] ? " The step stays cleared." : ""), action: "Clear " + n };
}
function clearAttempts() {
  var p = cur(), pid = p.id;
  return postJSON("/api/voice/clear", { prompt_id: pid }).then(function (j) {
      if (!j || j.error) throw new Error(j && j.error || "no answer");
      S.takes[pid] = []; S.fresh = null;
      var after = function () { alert("<b>Cleared " + j.archived + " takes.</b> They are in the archive, out of the list and the scores. The " + TRIES + "-take window starts fresh.", true, pid); };
      return stats().then(after, after);
    }).catch(function (e) { alert("<b>Nothing cleared.</b> " + esc(e && e.message || e) + ".", false, pid); });
}

// ---- wiring: one button ----
$("go").onclick = function () {
  if (S.rs === "recording") return stop();
  if (S.rs !== "idle") return;
  var p = cur();
  if (S.cleared[p.id] && !S.revisit) { go(firstOpen()); return; }
  start();
};
$("back").onclick = function () { go(S.idx - 1); };
$("resume").onclick = function () { go(firstOpen()); };
$("alert").onclick = function (e) { if (e.target.id === "dismiss") { S.alert = null; render(); } };
document.addEventListener("click", function (e) { var h = e.target.closest(".hear"); if (h) { play(h.dataset.wav); return; }
  if (e.target.id === "clearAsk") { ask(clearAsk()).then(function (ok) { if (ok) clearAttempts(); }); return; }
  var r = e.target.closest("#trailRows .row"); if (r) { go(parseInt(r.dataset.i, 10)); return; } var a = e.target.closest(".seg a"); if (a) { try { localStorage.setItem("voiceSection", a.dataset.sec); } catch (x) {} } });

getJSON("/api/voice/prompts?group=drill").then(function (j) { S.P = order(j); return Promise.all([stats(), progress()]); }).then(function () {
  S.idx = firstOpen(); S.ready = true; render(); var why = supported(); if (why) alert(why);
}).catch(function (e) { $("say").textContent = "could not load the path: " + e; });

// test hook: state and the forced step change used by the prompt-integrity test
window.__pron = { state: function () { return S; }, start: start, stop: stop, settle: settle, go: go, reachable: reachable, firstOpen: firstOpen, setElapsed: function (ms) { if (S.take) S.take.t0 = Date.now() - ms; }, render: render, earned: earned, order: order, clearAsk: clearAsk, clearAttempts: clearAttempts };

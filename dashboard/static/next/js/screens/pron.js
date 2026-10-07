/* Pronunciation screen: a linear path of drill steps, each cleared when every target word arrives. */
import {esc} from "/static/js/core/fmt.js";
import {getJSON, postJSON} from "/static/js/core/api.js";
import {ask} from "/static/js/ui/confirm.js";
import {$, lenOf, takesOf as takesIn, hhmm, stats as statsOf, alert as alertOn, paintAlert, paintStatus, diffHtml, band, scene as eyeScene, level, here, micWhy} from "../voice/common.js";
import {recorder, supported} from "../voice/recorder.js";
import {lens} from "../ui/num.js";
import {store} from "../store.js";

export const own = true, keep = true;
var PAT = ["final-consonant", "v-b", "ch-sh", "vowel"];
var PATNAME = { "final-consonant": "word endings", "v-b": "V not B", "ch-sh": "CH not SH", "vowel": "vowel shapes" };
var TRIES = 3;
var SHORT = { "final-consonant": "endings", "v-b": "v/b", "ch-sh": "ch/sh", "vowel": "vowels" };

// S is the whole screen state; paint() draws all of it. Nothing on screen is written anywhere else.
var S = { P: [], takes: {}, cleared: {}, idx: 0, rs: "idle", lead: 0, take: null, alert: null, fresh: null, session: 0, elapsed: 0, up: 0, cap: false, tx0: 0, stale: false, ready: false, revisit: false, takeHtml: "", booted: false };
var R = recorder({ S: S, cur: cur, render: paint, alert: alert, stats: stats, saved: settle, level: level,
  words: { item: "step", line: "the line above", refreshing: "refreshing…", list: "the step" } });
var start = R.start, stop = R.stop;

function cur() { return S.P[S.idx]; }
function takesOf(p) { return takesIn(S, p); }
function stats() { return statsOf(S); }
function alert(html, ok, pid) { alertOn(S, paint, html, ok, pid); }

export function render() {
  return '<div class="nxs vx" id="vx" data-rs="idle">' + band("Pronunciation") +
    '<nav class="vpath" aria-label="the 30-step path"><button class="sub nav" id="back" type="button" disabled>&lsaquo; back</button><div class="pbar" id="pbar" aria-hidden="true"></div><button class="sub nav" id="resume" type="button" hidden></button><span class="cnt" id="pathCount"></span></nav>' +
    '<section class="pane prompt short" id="prompt" data-rs="idle"><h2><span><span id="pos">…</span> <em id="grp"></em></span><span class="pill dim" id="len"></span></h2>' +
    '<p class="say" id="say">loading the path…</p>' +
    '<div class="listen" role="group" aria-labelledby="listenK"><span class="k" id="listenK">Listen</span><div class="lbtns"><button class="sub hear line" id="hearSay" type="button" aria-label="hear the sentence">&#9654; full line</button><div class="words" id="words"></div></div></div>' +
    '<p class="rule" id="rule">Say every marked word right in one take — or across three takes — and the next step opens.</p>' +
    '<div class="status"><i class="dot"></i><span class="txt" id="stateText">loading</span><span class="timer" id="timer"></span></div><div class="meter"><i id="meter"></i></div></section>' +
    '<section class="alert" id="alert" role="alert" hidden></section>' +
    '<section class="pane takes" id="takes" hidden><h2>This step <s id="takeCount"></s></h2><div id="takeList"></div><div id="clearBox"></div>' +
    '<p class="legend" id="legend" hidden><i class="gold">gold</i> = you said it, it missed or changed it &middot; <i class="vio">violet</i> = it heard a word you did not say</p></section>' +
    '<details class="pane drawer" id="prog" hidden><summary>Errors per 100 target words <s id="progSum"></s></summary><div class="pgrid" id="progGrid"></div></details>' +
    '<details class="pane drawer" id="steps" hidden><summary>Cleared steps <s id="trailCount"></s></summary><div class="list" id="trailRows"></div></details>' +
    '<div class="vbar" role="toolbar" aria-label="Recording"><button class="go" id="go" type="button" disabled><span id="goLabel">Continue</span><em id="goSub"></em></button></div></div>';
}

/* First visit loads the path; every visit paints the state kept since. */
export function enter() {
  if (!$("vx")) return;
  if (!S.booted) { S.booted = true; boot(); return; }
  if (S.ready) { S.takeHtml = ""; paint(); }
}
function boot() {
  getJSON("/api/voice/prompts?group=drill").then(function (j) { S.P = order(j); return Promise.all([stats(), progress()]); }).then(function () {
    S.idx = firstOpen(); S.ready = true; paint(); store.rescene(); var why = micWhy(supported(), "pronunciation"); if (why) alert(why);
  }).catch(function (e) { S.booted = false; if ($("say")) $("say").textContent = "could not load the path: " + e; });
}
export function scene() { return eyeScene(clearedCount(), S.P.length); }

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
function go(i) { if (!reachable(i)) return; S.idx = i; S.revisit = i !== firstOpen(); S.alert = null; S.fresh = null; paint(); window.scrollTo(0, 0); }
function firstOpen() { for (var i = 0; i < S.P.length; i++) if (!S.cleared[S.P[i].id]) return i; return S.P.length - 1; }
function clearedCount() { return S.P.filter(function (p) { return S.cleared[p.id]; }).length; }

function progress() {
  return getJSON("/api/voice/progress").then(function (j) { S.cleared = (j && j.cleared) || {}; }, function () {});
}
function markCleared(p) {
  S.cleared[p.id] = new Date().toISOString();
  return postJSON("/api/voice/progress", { cleared: p.id }).then(function (j) { if (j && j.cleared) S.cleared = j.cleared; store.rescene(); }, function () {});
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
  return '<button class="sub hear" type="button" data-wav="' + esc(file) + '" aria-label="hear ' + esc(label) + '">&#9654; ' + esc(label) + "</button>";
}

function verdictHtml(t, p) {
  var v = t.verdict;
  if (!Array.isArray(v) || !v.length) return "";
  var hit = v.filter(function (x) { return x.status === "hit"; }).length;
  var miss = v.filter(function (x) { return x.status !== "hit"; }), got = v.filter(function (x) { return x.status === "hit"; });
  var head = miss.length ? '<span class="k gold">replay these ' + miss.length + "</span>" : '<span class="k">' + hit + " of " + v.length + " target words right</span>";
  return '<div class="verd">' + head + miss.concat(got).map(function (x) {
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
  var g = PAT.map(function (k) {
    var a = acc[k], per = a.seen ? Math.round(a.miss / a.seen * 100) : null;
    return '<div class="pat">' + lens(per || 0, per === null ? "—" : String(per), PATNAME[k] + ": " + (per === null ? "nothing recorded yet" : per + " errors per 100 target words"), per > 0) +
      "<em>" + PATNAME[k] + "</em><s>" + (per === null ? "nothing recorded yet" : (a.seen - a.miss) + " of " + a.seen + " target words right") + "</s></div>";
  }).join("");
  if ($("progGrid").innerHTML !== g) $("progGrid").innerHTML = g;
  $("progSum").innerHTML = PAT.map(function (k) { var a = acc[k], per = a.seen ? Math.round(a.miss / a.seen * 100) : null; return SHORT[k] + " " + (per === null ? "—" : per > 0 ? "<u>" + per + "</u>" : per); }).join(" · ");
}

// ---- the trail: steps already cleared; tap one to record it again ----
function renderTrail() {
  var done = S.P.map(function (p, i) { return { p: p, i: i }; }).filter(function (x) { return S.cleared[x.p.id]; });
  $("steps").hidden = !done.length;
  if (!done.length) return;
  $("trailCount").textContent = done.length + " of " + S.P.length;
  $("trailRows").innerHTML = done.map(function (x) {
    return '<button class="row ok' + (x.i === S.idx ? " cur" : "") + '" type="button" data-i="' + x.i + '"><span class="n">' + (x.i + 1) + '</span><span class="t">' + esc(x.p.text) + '</span><span class="pill">' + (x.i === S.idx ? "open" : "cleared") + '</span></button>';
  }).join("");
}

// ---- painting ----
function paint() {
  if (!here(S, R, "vx")) return;
  var p = cur(); if (!p) return;
  var L = lenOf(p), list = takesOf(p), busy = S.rs !== "idle", done = !!S.cleared[p.id], tries = list.length;
  var card = $("prompt");
  card.className = "pane prompt " + (p.len === "long" ? "long" : "short") + (done ? " done" : tries ? " bad" : "");
  card.dataset.rs = S.rs; $("vx").dataset.rs = S.rs;
  $("pos").textContent = "step " + (S.idx + 1) + " of " + S.P.length;
  $("grp").textContent = PATNAME[p.pattern] || p.pattern;
  $("len").textContent = (p.targets || []).length + " target words"; $("len").className = "pill dim";
  if ($("say").textContent !== p.text) $("say").textContent = p.text;
  $("hearSay").dataset.wav = "s-" + p.id + ".wav";
  var wh = (p.targets || []).map(function (t) { return hearBtn("w-" + slug(t.word) + ".wav", t.word); }).join("");
  if ($("words").innerHTML !== wh) $("words").innerHTML = wh;
  $("rule").textContent = S.revisit ? "Cleared step, reopened. Record it again — your place on the path stays at step " + (firstOpen() + 1) + "." :
    done ? "Cleared. Continue opens step " + Math.min(S.P.length, firstOpen() + 1) + "." :
    "This step clears when every marked word arrives — all of them in one take, or across " + TRIES + " takes.";
  $("vsum").innerHTML = "step <b>" + (S.idx + 1) + "</b> of " + S.P.length + " · " + esc(PATNAME[p.pattern] || p.pattern) + " · <b>" + clearedCount() + "</b> cleared";

  paintStatus(S, L, S.revisit ? "reopened · record this step again" : done ? "step cleared · tap continue for the next one" : !tries ? "tap continue, read the line, tap stop" : "not cleared yet · say it again");
  paintAlert(S, p);

  $("takeCount").textContent = tries ? "take " + Math.min(tries, TRIES) + " of " + TRIES : "nothing said yet";
  $("takes").hidden = !list.length;
  $("legend").hidden = !list.length;
  var th = list.slice(0, TRIES).map(function (t, i) { return takeCard(t, list.length - i, i === 0); }).join("");
  if (S.takeHtml !== th) { S.takeHtml = th; $("takeList").innerHTML = th; }
  $("clearBox").innerHTML = !list.length || busy ? "" :
    '<div class="acts clr"><button class="sub" type="button" id="clearAsk">Clear attempts</button></div>';

  var g = $("go");
  g.className = "go" + (S.rs === "recording" ? " on" : busy ? " busy" : done ? " done" : "");
  g.disabled = !S.ready || S.rs === "arming" || S.rs === "uploading" || S.rs === "transcribing";
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

// ---- wiring: clicks reach the screen through the shell ----
export function click(e) {
  var t = e.target, b = t.closest("button");
  if (!b || !$("vx") || !$("vx").contains(b)) return false;
  if (b.id === "go") {
    if (S.rs === "recording") stop();
    else if (S.rs === "idle") { var p = cur(); if (S.cleared[p.id] && !S.revisit) go(firstOpen()); else start(); }
  } else if (b.id === "back") go(S.idx - 1);
  else if (b.id === "resume") go(firstOpen());
  else if (b.id === "dismiss") { S.alert = null; paint(); }
  else if (b.classList.contains("hear")) play(b.dataset.wav);
  else if (b.id === "clearAsk") ask(clearAsk()).then(function (ok) { if (ok) clearAttempts(); });
  else if (b.dataset.i != null) go(parseInt(b.dataset.i, 10));
  else return false;
  return true;
}
/* While a take is running, the keys never move the screen away. */
export function key() { return S.rs !== "idle"; }

// test hook: state and the forced step change used by the prompt-integrity test
window.__pron = { state: function () { return S; }, start: start, stop: stop, settle: settle, go: go, reachable: reachable, firstOpen: firstOpen, setElapsed: function (ms) { if (S.take) S.take.t0 = Date.now() - ms; }, render: paint, earned: earned, order: order, clearAsk: clearAsk, clearAttempts: clearAttempts };

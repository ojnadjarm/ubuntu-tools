/* Record screen: read each corpus prompt aloud, keep or redo its takes. */
import {esc} from "/static/js/core/fmt.js";
import {getJSON, postJSON} from "/static/js/core/api.js";
import {ask} from "/static/js/ui/confirm.js";
import {$, lenOf, takesOf as takesIn, wrong, hhmm, stats as statsOf, alert as alertOn, paintAlert, paintStatus, diffHtml, band, scene as eyeScene, level, here, micWhy} from "../voice/common.js";
import {recorder, supported} from "../voice/recorder.js";
import {store} from "../store.js";

export const own = true, keep = true;

// S is the whole screen state; paint() draws all of it. Nothing on screen is written anywhere else.
var S = { P: [], takes: {}, idx: 0, rs: "idle", lead: 0, take: null, alert: null, fresh: null, session: 0, elapsed: 0, up: 0, cap: false, tx0: 0, stale: false, booted: false, listHtml: "", takeHtml: "" };
var R = recorder({ S: S, cur: cur, render: paint, alert: alert, stats: stats, saved: saved, level: level,
  words: { item: "prompt", line: "the prompt above", refreshing: "refreshing the take list…", list: "the take list" } });
var start = R.start, stop = R.stop;

function cur() { return S.P[S.idx]; }
function takesOf(p) { return takesIn(S, p); }
function grade(t) { if (t.transcript == null) return "none"; var g = wrong(t); return g.wrong || g.extra ? "bad" : "good"; }
function best(p) { var g = null; takesOf(p).forEach(function (t) { var k = grade(t); if (k === "good") g = "good"; else if (k === "bad" && g !== "good") g = "bad"; else if (!g) g = "none"; }); return g; }
function stats() { return statsOf(S); }
function alert(html, ok, pid) { alertOn(S, paint, html, ok, pid); }

function save() { try { localStorage.setItem("voiceIdx", String(S.idx)); } catch (e) {} }
function restore() { try { var i = parseInt(localStorage.getItem("voiceIdx"), 10); if (i >= 0 && i < S.P.length) S.idx = i; } catch (e) {} }

export function render() {
  return '<div class="nxs vx" id="vx" data-rs="idle">' + band("Record") +
    '<section class="pane prompt short" id="prompt" data-rs="idle"><h2><span><span id="pos">…</span> <em id="grp"></em></span><span class="pill dim" id="len"></span></h2>' +
    '<p class="say" id="say">loading prompts…</p>' +
    '<div class="status"><i class="dot"></i><span class="txt" id="stateText">loading</span><span class="timer" id="timer"></span></div><div class="meter"><i id="meter"></i></div></section>' +
    '<section class="alert" id="alert" role="alert" hidden></section>' +
    '<section class="pane takes"><h2>Takes of this prompt <s id="takeCount"></s></h2><div id="takeList"></div>' +
    '<p class="legend" id="legend" hidden><i class="gold">gold</i> = you said it, it missed or changed it &middot; <i class="vio">violet</i> = it heard a word you did not say</p></section>' +
    '<details class="pane drawer" id="sheet"><summary>Your session <s id="sessSum"></s></summary>' +
    '<div class="sum"><div><b id="sRec">0</b><em>recorded</em></div><div><b class="gold" id="sBad">0</b><em>need a redo</em></div><div><b class="dim" id="sTodo">0</b><em>to go</em></div></div>' +
    '<p class="hint" id="sHint"></p><div class="list" id="list"></div></details>' +
    '<div class="vbar recbar" role="toolbar" aria-label="Recording"><button class="sub nav" id="back" type="button">&lsaquo; back</button>' +
    '<button class="rec" id="rec" type="button" aria-pressed="false" disabled><i></i><span id="recLabel">record</span></button><button class="sub nav" id="next" type="button">next &rsaquo;</button></div></div>';
}

/* First visit loads the prompts; every visit paints the state kept since. */
export function enter() {
  if (!$("vx")) return;
  if (!S.booted) { S.booted = true; boot(); return; }
  if (S.ready) { S.listHtml = S.takeHtml = ""; paint(); }
}
function boot() {
  getJSON("/api/voice/prompts").then(function (j) { S.P = j; return stats(); }).then(function () {
    restore(); S.ready = true; paint(); store.rescene(); var why = micWhy(supported(), "record"); if (why) alert(why);
  }).catch(function (e) { S.booted = false; if ($("say")) $("say").textContent = "could not load the prompts: " + e; });
}
export function scene() { return eyeScene(S.P.filter(function (p) { return best(p); }).length, S.P.length); }

function go(i, force) {
  if (S.rs !== "idle" && !force) return false;
  if (i < 0 || i >= S.P.length) return false;
  S.idx = i; S.alert = null; S.fresh = null; save(); paint();
  window.scrollTo(0, 0);
  return true;
}

// ---- painting ----
function paint() {
  if (!here(S, R, "vx")) return;
  var p = cur(); if (!p) return;
  var L = lenOf(p), list = takesOf(p), busy = S.rs !== "idle", b = best(p);
  var card = $("prompt");
  card.className = "pane prompt " + (p.len === "long" ? "long" : "short") + (b === "good" ? " done" : b === "bad" ? " bad" : "");
  card.dataset.rs = S.rs; $("vx").dataset.rs = S.rs;
  $("pos").textContent = (S.idx + 1) + " / " + S.P.length;
  $("grp").textContent = p.group;
  $("len").textContent = L.label; $("len").className = "pill " + (p.len === "long" ? "gold" : "dim");
  if ($("say").textContent !== p.text) $("say").textContent = p.text;

  paintStatus(S, L, !list.length ? "not recorded yet · tap record, read it, tap stop" : b === "good" ? "good take on disk · next when you are ready" : b === "bad" ? "no clean take yet · redo or move on" : "recorded, not transcribed");
  paintAlert(S, p);

  $("takeCount").textContent = list.length ? list.length + (list.length === 1 ? " take" : " takes") + " · newest first" : "none yet";
  $("legend").hidden = !list.some(function (t) { return grade(t) === "bad"; });
  var th = list.length ? list.map(function (t, i) { return takeCard(t, list.length - i); }).join("") :
    '<div class="empty">' + (busy ? "your take lands here when it is saved" : "No takes of this prompt yet.<br>Tap <b>record</b>, read the line above, tap <b>stop</b>.<br>It stays here until you say otherwise.") + "</div>";
  if (S.takeHtml !== th) { S.takeHtml = th; $("takeList").innerHTML = th; }

  var recBtn = $("rec");
  recBtn.className = "rec" + (S.rs === "recording" ? " on" : S.rs === "idle" ? "" : " busy");
  recBtn.disabled = S.rs === "arming" || S.rs === "uploading" || S.rs === "transcribing" || !S.ready;
  recBtn.setAttribute("aria-pressed", S.rs === "recording" ? "true" : "false");
  $("recLabel").textContent = S.rs === "recording" ? "stop" : S.rs === "idle" ? (list.length ? "again" : "record") : S.rs === "arming" ? "mic…" : "wait";
  $("back").disabled = busy || S.idx === 0;
  $("next").disabled = busy || S.idx >= S.P.length - 1;

  if (!busy) paintSession();
}

function takeCard(t, n) {
  var g = grade(t), w = wrong(t), verdict = g === "none" ? '<span class="pill dim">no transcript</span>' : g === "good" ? '<span class="pill">all ' + w.said + " words right</span>" : '<span class="pill gold">' + w.wrong + " of " + w.said + " wrong" + (w.extra ? " · +" + w.extra + " extra" : "") + "</span>";
  var foot = '<div class="acts"><button class="sub" type="button" data-act="redo" data-n="' + n + '" data-id="' + esc(t.id) + '">redo take ' + n + '</button><button class="sub" type="button" data-act="del" data-n="' + n + '" data-id="' + esc(t.id) + '">delete take ' + n + "</button></div>";
  return '<article class="take ' + g + (S.fresh === t.id ? " fresh" : "") + '" data-id="' + esc(t.id) + '"><header><b>take ' + n + '</b><span class="when">' + esc(hhmm(t.recorded_at)) + " · " + esc(t.seconds) + " s</span>" + verdict + "</header>" + diffHtml(t, "you said", true) + foot + "</article>";
}

/* The session: counts, the band line and the prompt list to jump anywhere. */
function paintSession() {
  var rec = 0, bad = 0;
  S.P.forEach(function (p) { var b = best(p); if (b) { rec++; if (b !== "good") bad++; } });
  $("sRec").textContent = rec; $("sBad").textContent = bad; $("sTodo").textContent = S.P.length - rec;
  $("sessSum").textContent = rec + " of " + S.P.length + " recorded" + (bad ? " · " + bad + " to redo" : "");
  $("vsum").innerHTML = "prompt <b>" + (S.idx + 1) + "</b> of " + S.P.length + " · <b>" + rec + "</b> recorded" + (bad ? " · " + bad + " need a redo" : "");
  $("sHint").textContent = !rec ? "Nothing recorded yet — " + S.P.length + " prompts waiting. Tap one to start there." : (S.clips || 0) + " clip" + (S.clips === 1 ? "" : "s") + " on disk · " + Math.round(S.seconds || 0) + " s of your speech · " + S.session + " this visit. Tap a prompt to go to it.";
  var h = S.P.map(function (p, i) {
    var b = best(p), pill = !b ? '<span class="pill dim">to do</span>' : b === "good" ? '<span class="pill">good</span>' : b === "bad" ? '<span class="pill gold">redo</span>' : '<span class="pill vio">no text</span>';
    return '<button class="row ' + (b === "bad" ? "bad" : b ? "ok" : "todo") + (i === S.idx ? " cur" : "") + '" type="button" data-i="' + i + '"><span class="n">' + (i + 1) + '</span><span class="t">' + esc(p.text) + "</span>" + pill + "</button>";
  }).join("");
  if (S.listHtml === h) return;
  S.listHtml = h;
  var L = $("list"), c;
  L.innerHTML = h;
  c = L.querySelector(".cur");
  if (c) L.scrollTop = c.offsetTop - L.clientHeight / 2;
}

function saved(j, t) {
  var g = grade(j), w = wrong(j);
  var heard = j.transcript == null ? "" : ' It heard <q>' + esc(j.transcript) + "</q>";
  var msg = g === "good" ? "<b>Saved, all " + w.said + " words right.</b>" + heard + " Next when you are ready, or record it again." : g === "bad" ? "<b>Saved.</b> " + w.wrong + " of " + w.said + " words came out wrong." + heard + " The word diff is in take " + takesOf(cur()).length + " below. Redo it, or move on." : "<b>Saved,</b> but the transcriber did not answer, so there is nothing to compare. The clip is kept as take " + takesOf(cur()).length + " below.";
  alert(msg + " Clip " + esc(j.id) + ", " + esc(j.seconds) + " s.", g === "good", t.id);
  stats().then(function () { paint(); store.rescene(); }, function () { if (!cur() || cur().id !== t.id) return; alert(msg + " (The take list could not refresh from the machine; what you see is this visit only.)", g === "good", t.id); });
}

/* The designed confirm for a delete or a redo of take n. */
function delAsk(n, redo) {
  return { title: redo ? "Redo take " + n + "?" : "Delete take " + n + "?", item: "take " + n + " of prompt " + (S.idx + 1),
    body: redo ? "It is deleted and the microphone opens for a new take." : "It leaves the list and the scores for good.", action: redo ? "Delete and record" : "Delete" };
}
function del(id, thenRecord) {
  return postJSON("/api/voice/delete", { id: id }).catch(function (e) { if (e.status !== 404) throw e.status ? new Error("HTTP " + e.status) : e; }).then(function () {
    S.session = Math.max(0, S.session - 1);
    return stats();
  }).then(function () { if (thenRecord) start(); else alert("<b>Take " + esc(id) + " deleted.</b>", true); }, function (e) { alert("<b>Could not delete</b> " + esc(id) + ": " + esc(e.message)); });
}

// ---- wiring: clicks reach the screen through the shell ----
export function click(e) {
  var b = e.target.closest("button");
  if (!b || !$("vx") || !$("vx").contains(b)) return false;
  var act = b.dataset.act;
  if (b.id === "rec") { if (S.rs === "recording") stop(); else if (S.rs === "idle") start(); }
  else if (b.id === "back") go(S.idx - 1);
  else if (b.id === "next") go(S.idx + 1);
  else if (b.id === "dismiss") { S.alert = null; paint(); }
  else if (b.dataset.i != null) { if (go(parseInt(b.dataset.i, 10))) $("sheet").open = false; }
  else if (act && S.rs === "idle") { var id = b.dataset.id; ask(delAsk(b.dataset.n, act === "redo")).then(function (ok) { if (ok && S.rs === "idle") del(id, act === "redo"); }); }
  else return false;
  return true;
}
/* While a take is running, the keys never move the screen away. */
export function key() { return S.rs !== "idle"; }

// test hook: state and the forced prompt change used by the prompt-integrity test
window.__voice = { state: function () { return S; }, go: go, start: start, stop: stop, setElapsed: function (ms) { if (S.take) S.take.t0 = Date.now() - ms; }, render: paint, delAsk: delAsk };

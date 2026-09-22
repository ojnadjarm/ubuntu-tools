/* Microphone capture with the lead-in, the size and prompt checks, and the clip upload. */
import {esc} from "../core/fmt.js";
import {postJSON} from "../core/api.js";
import {LEADIN, lenOf} from "./common.js";

export function supported() {
  if (!window.isSecureContext) return "The microphone only works on a secure page. Open the <b>https</b> tailnet link (port 8498), not the plain LAN address.";
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return "This browser has no microphone API.";
  if (typeof MediaRecorder === "undefined") return "This browser cannot record audio (no MediaRecorder).";
  return "";
}
function mime() { var c = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"]; for (var i = 0; i < c.length; i++) if (MediaRecorder.isTypeSupported(c[i])) return c[i]; return ""; }
function sha256(text) {
  if (!window.crypto || !crypto.subtle) return Promise.resolve(null);
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)).then(function (buf) { return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ("0" + b.toString(16)).slice(-2); }).join(""); }).catch(function () { return null; });
}

/* o: {S, cur(), render(), alert(html, ok, pid), stats(), saved(j) after a clip is filed, words: page nouns in the messages} */
export function recorder(o) {
  var S = o.S, W = o.words, rec = null, chunks = [], tick = null, xhr = null;

  function start() {
    var why = supported(); if (why) { o.alert(why); return; }
    var p = o.cur();
    S.take = { id: p.id, text: p.text, sha: null, t0: 0, ms: 0 };
    S.alert = null; S.confirm = null; S.fresh = null; S.rs = "arming"; S.cap = false; S.lead = 0; o.render();
    window.scrollTo(0, 0);
    sha256(p.text).then(function (h) { S.take.sha = h; return navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } }); }).then(function (s) {
      if (S.rs !== "arming") { s.getTracks().forEach(function (t) { t.stop(); }); return; }
      chunks = []; var m = mime(); rec = new MediaRecorder(s, m ? { mimeType: m } : undefined);
      rec.ondataavailable = function (e) { if (e.data && e.data.size) chunks.push(e.data); };
      rec.onerror = function (e) { fail("<b>Recording broke:</b> " + esc(e && e.error && e.error.name || e && e.name || "unknown error") + ". Nothing saved — say it again."); };
      rec.onstop = function () { s.getTracks().forEach(function (t) { t.stop(); }); finish(new Blob(chunks, { type: rec.mimeType || m || "audio/webm" })); };
      S.lead = LEADIN; o.render();
      var lead0 = Date.now();
      tick = setInterval(function () {
        S.lead = Math.max(0, LEADIN - (Date.now() - lead0));
        if (S.lead > 0) { o.render(); return; }
        clearInterval(tick);
        rec.start(250); S.take.t0 = Date.now(); S.elapsed = 0; S.rs = "recording"; o.render();
        tick = setInterval(function () { S.elapsed = Date.now() - S.take.t0; if (S.elapsed >= lenOf(p).max) { S.cap = true; stop(); } o.render(); }, 100);
      }, 100);
    }).catch(function (e) {
      var name = e && e.name || "";
      if (name === "NotAllowedError" || name === "SecurityError") fail("<b>Microphone blocked.</b> The browser refused the mic for this page. Tap the lock icon in the address bar → Microphone → Allow, then reload. Nothing was recorded.");
      else if (name === "NotFoundError") fail("<b>No microphone found.</b> Connect one and reload.");
      else fail("<b>Could not open the microphone:</b> " + esc(name || e));
    });
  }
  function stop() { clearInterval(tick); tick = null; if (rec && rec.state !== "inactive") rec.stop(); }
  function fail(html) { clearInterval(tick); tick = null; S.rs = "idle"; S.take = null; o.alert(html); }

  function finish(blob) {
    var t = S.take; t.ms = Date.now() - t.t0;
    if (!t || o.cur().id !== t.id) { fail("<b>Take discarded.</b> The " + W.item + " on screen changed while you were recording (you were reading “" + esc(t && t.text || "") + "”). Nothing was saved. Read " + W.line + " and record it again."); return; }
    if (t.ms < 500 || blob.size < 1000) { fail("<b>Too short, nothing saved.</b> Hold it for at least half a second."); return; }
    S.rs = "uploading"; S.up = 0; S.tx0 = Date.now(); clearInterval(tick); tick = setInterval(o.render, 250); o.render();
    xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/voice/clip"); xhr.timeout = 90000;
    xhr.setRequestHeader("Content-Type", blob.type || "audio/webm");
    xhr.setRequestHeader("X-Prompt-Id", t.id);
    if (t.sha) xhr.setRequestHeader("X-Prompt-Sha", t.sha);
    xhr.upload.onprogress = function (e) { if (e.lengthComputable) { S.up = Math.round(e.loaded / e.total * 100); o.render(); } };
    xhr.upload.onload = function () { S.up = 100; S.rs = "transcribing"; S.tx0 = Date.now(); o.render(); };
    xhr.onerror = function () { fail("<b>NOT SAVED.</b> The phone could not reach the machine. Check the tailnet link and say it again."); };
    xhr.ontimeout = function () { fail("<b>NOT SAVED.</b> No answer from the machine after 90 s. Say it again."); };
    xhr.onload = function () {
      clearInterval(tick); tick = null;
      var j; try { j = JSON.parse(xhr.responseText); } catch (e) { j = null; }
      if (!j || typeof j !== "object") {
        S.rs = "idle"; S.take = null;
        o.alert("<b>Unreadable answer from the machine</b> (HTTP " + xhr.status + "). The clip may be on disk — " + W.refreshing + " If it is not below, say it again.", false, t.id);
        o.stats().then(o.render, function () { o.alert("<b>Unreadable answer from the machine</b> (HTTP " + xhr.status + ") and " + W.list + " could not refresh. Reload the page.", false, t.id); });
        return;
      }
      if (xhr.status !== 200) { fail("<b>NOT SAVED.</b> The machine refused the clip: " + esc(j.error || xhr.status) + ". Say it again."); return; }
      if (j.prompt_id !== t.id) { fail("<b>NOT SAVED.</b> The machine filed the clip under another " + W.item + " (" + esc(j.prompt_id) + "); it was deleted. Say it again."); postJSON("/api/voice/delete", { id: j.id }).catch(function () {}); return; }
      S.session++;
      S.takes[t.id] = (S.takes[t.id] || []).filter(function (x) { return x.id !== j.id; }).concat([j]);
      S.rs = "idle"; S.take = null; S.fresh = j.id;
      o.saved(j, t);
    };
    xhr.send(blob);
  }

  return { start: start, stop: stop };
}

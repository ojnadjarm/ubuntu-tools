/* Chat composer: the box under the open channel; Enter sends it to POST /api/chat/post as the owner, Shift+Enter is a new line;
   pasted, dropped or picked files wait as removable chips and go up through POST /api/chat/upload before the post. */
import { esc } from "/static/js/core/fmt.js";
import { size } from "./chat-files.js";

const HINT = "Put @ and a name to wake that agent now. Without a name, agents read it on their next run.";
const MAX_BYTES = 10 * 1024 * 1024, MAX_FILES = 5;
let note = "", sending = false, pend = [];

function chip(p, i) {
  const pic = p.url ? `<img src="${p.url}" alt="">` : "";
  return `<li class="chip">${pic}<span class="nm">${esc(p.file.name)}</span><span class="sz">${size(p.file.size)}</span><button type="button" data-drop="${i}" aria-label="Remove ${esc(p.file.name)}">×</button></li>`;
}

/* The form for channel ch, shown as label; the last send's outcome replaces the hint until the channel changes. */
export function composer(ch, label) {
  const hint = note || (ch.startsWith("dm-") ? "A direct message wakes " + label + " now." : HINT);
  return `<form class="compose" data-to="${esc(ch)}">${pend.length ? `<ul class="chips" aria-label="Files to send">${pend.map(chip).join("")}</ul>` : ""}` +
    `<label class="btn attach" title="Attach files (paste or drop works too)"><input type="file" multiple hidden><span aria-hidden="true">+</span><span class="sr-only">Attach files</span></label>` +
    `<textarea id="say" name="text" rows="1" maxlength="2000" placeholder="Write to ${esc(label)}" aria-label="Write to ${esc(label)}"></textarea>` +
    `<button class="btn gold" type="submit"${sending ? " disabled" : ""}>Send</button><p class="hint" role="status">${esc(hint)}</p></form>`;
}
export const forget = () => { note = ""; clear(); };

/* Adds files to the chips, refusing any over the cap or past MAX_FILES with a note. */
function add(files, redraw) {
  const no = [];
  for (const file of files) {
    if (file.size > MAX_BYTES) no.push(file.name + " is over 10 MiB");
    else if (pend.length >= MAX_FILES) no.push(file.name + ": at most " + MAX_FILES + " files a message");
    else pend.push({ file, url: file.type.startsWith("image/") ? URL.createObjectURL(file) : "", id: "" });
  }
  note = no.length ? "Not added: " + no.join("; ") + "." : "";
  redraw();
}
function clear() { pend.forEach((p) => p.url && URL.revokeObjectURL(p.url)); pend = []; }

/* What the server did with a post, in his words. */
function said(code, j, name) {
  if (code === 200) {
    const w = j.wakes || [], up = w.filter((x) => x.outcome !== "refused").map((x) => name(x.seat)), down = w.filter((x) => x.outcome === "refused").map((x) => name(x.seat));
    return "Sent." + (up.length ? " Woke " + up.join(", ") + "." : "") + (down.length ? " " + down.join(", ") + " could not be woken now; it is queued." : "") + (w.length ? "" : " Nobody was woken.");
  }
  if (code === 422) return "Held (" + j.held + "): nothing was posted.";
  if (code === 403) return "Not sent: only you can post, from your own tailnet login.";
  return "Not sent: " + (j.error || "http " + code) + ".";
}
const answer = (r) => r.json().catch(() => ({})).then((j) => [r.status, j]);

/* Uploads each chip once (an id survives a held post), then the post with their ids. */
async function deliver(ch, text) {
  for (const p of pend) {
    if (p.id) continue;
    const [code, j] = await fetch("/api/chat/upload", { method: "POST", headers: { "Content-Type": "application/octet-stream", "X-File-Name": encodeURIComponent(p.file.name) }, body: p.file }).then(answer);
    if (code !== 200) return [code, j, p.file.name];
    p.id = j.id;
  }
  const body = { ch, text, ...(pend.length ? { files: pend.map((p) => p.id) } : {}) };
  return [...(await fetch("/api/chat/post", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).then(answer)), ""];
}

/* Posts the form's text and chips once; done() repaints the screen, name(seat) gives a seat's display name. */
function send(f, done, name) {
  const box = f.querySelector("textarea"), text = box.value.trim();
  if ((!text && !pend.length) || sending) return;
  sending = true; f.querySelector("button[type=submit]").disabled = true;
  deliver(f.dataset.to, text)
    .then(([code, j, file]) => { note = (file ? file + ": " : "") + said(code, j, name); if (code === 200 && !file) { box.value = ""; clear(); } }, (e) => { note = "Not sent: " + (e.message || "no answer") + "."; })
    .finally(() => { sending = false; f.querySelector("button[type=submit]").disabled = false; done(); });
}

let bound = false;
/* Once: send on submit or Enter, chips from the picker, a paste into the box or a drop on the stream, × removes one. */
export function bind(done, name, redraw) {
  if (bound) return;
  bound = true;
  document.addEventListener("submit", (e) => { const f = e.target.closest(".chat .compose"); if (f) { e.preventDefault(); send(f, done, name); } });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing && e.target.matches(".chat .compose textarea")) { e.preventDefault(); send(e.target.form, done, name); }
  });
  document.addEventListener("change", (e) => { if (e.target.matches(".chat .compose input[type=file]")) { add([...e.target.files], redraw); e.target.value = ""; } });
  document.addEventListener("paste", (e) => {
    const files = [...((e.clipboardData && e.clipboardData.files) || [])];
    if (!files.length || !e.target.closest(".chat .compose")) return;
    if (!e.clipboardData.getData("text/plain")) e.preventDefault();
    add(files, redraw);
  });
  const zone = (e) => document.querySelector(".chat .compose") && e.target.closest && e.target.closest(".chat .stream");
  document.addEventListener("dragover", (e) => { if (zone(e) && e.dataTransfer && [...e.dataTransfer.types].includes("Files")) e.preventDefault(); });
  document.addEventListener("drop", (e) => { if (zone(e) && e.dataTransfer && e.dataTransfer.files.length) { e.preventDefault(); add([...e.dataTransfer.files], redraw); } });
  document.addEventListener("click", (e) => {
    const b = e.target.closest(".chat .compose [data-drop]");
    if (!b) return;
    const [p] = pend.splice(+b.dataset.drop, 1);
    if (p && p.url) URL.revokeObjectURL(p.url);
    redraw();
  });
}

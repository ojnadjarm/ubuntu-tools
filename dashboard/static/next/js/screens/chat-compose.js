/* Chat composer: the box under the open channel; Enter sends it to POST /api/chat/post as the owner, Shift+Enter is a new line. */
import { esc } from "/static/js/core/fmt.js";

const HINT = "Put @ and a name to wake that agent now. Without a name, agents read it on their next run.";
let note = "", sending = false;

/* The form for channel ch, shown as label; the last send's outcome replaces the hint until the channel changes. */
export function composer(ch, label) {
  const hint = note || (ch.startsWith("dm-") ? "A direct message wakes " + label + " now." : HINT);
  return `<form class="compose" data-to="${esc(ch)}"><textarea id="say" name="text" rows="1" maxlength="2000" placeholder="Write to ${esc(label)}" aria-label="Write to ${esc(label)}"></textarea>` +
    `<button class="btn gold" type="submit"${sending ? " disabled" : ""}>Send</button><p class="hint" role="status">${esc(hint)}</p></form>`;
}
export const forget = () => { note = ""; };

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

/* Posts the form's text once; done() repaints the screen, name(seat) gives a seat's display name. */
function send(f, done, name) {
  const box = f.querySelector("textarea"), text = box.value.trim();
  if (!text || sending) return;
  sending = true; f.querySelector("button").disabled = true;
  fetch("/api/chat/post", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ch: f.dataset.to, text }) })
    .then((r) => r.json().catch(() => ({})).then((j) => { note = said(r.status, j, name); if (r.ok) box.value = ""; }), (e) => { note = "Not sent: " + (e.message || "no answer") + "."; })
    .finally(() => { sending = false; f.querySelector("button").disabled = false; done(); });
}

let bound = false;
export function bind(done, name) {
  if (bound) return;
  bound = true;
  document.addEventListener("submit", (e) => { const f = e.target.closest(".chat .compose"); if (f) { e.preventDefault(); send(f, done, name); } });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing && e.target.matches(".chat .compose textarea")) { e.preventDefault(); send(e.target.form, done, name); }
  });
}

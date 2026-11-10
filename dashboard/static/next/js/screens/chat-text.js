/* Chat message text to safe HTML (T1545-B): escaped, then http(s) links, fenced code blocks with Copy, `code` spans. */
import { esc } from "/static/js/core/fmt.js";
import { copyText, copied } from "/static/js/ui/copy.js";

const FENCE = /(?<=^|\n)```([\w+#.-]*)[ \t]*\n(?:([\s\S]*?)\n)?```[ \t]*(?=\n|$)\n?/g;
const URL_RE = /\bhttps?:\/\/[^\s<>"'`]+/gi;
const LINK = ' target="_blank" rel="noopener noreferrer"';

/* Escaped text with http(s) URLs as links; trailing .,;:) stays outside. */
function links(t) {
  let out = "", at = 0;
  for (const m of t.matchAll(URL_RE)) {
    const u = m[0].replace(/[.,;:)]+$/, "");
    out += esc(t.slice(at, m.index)) + `<a href="${esc(u)}"${LINK}>${esc(u)}</a>`;
    at = m.index + u.length;
  }
  return out + esc(t.slice(at));
}

/* Inline text: backtick spans become code, the rest gets links. */
const inline = (t) => t.split(/`([^`\n]+)`/).map((s, i) => (i % 2 ? `<code>${esc(s)}</code>` : links(s))).join("");

/* Message text as safe HTML for a white-space: pre-line container. */
export function rich(text) {
  const t = String(text == null ? "" : text);
  let out = "", at = 0;
  for (const m of t.matchAll(FENCE)) {
    out += inline(t.slice(at, m.index).replace(/\n$/, "")) +
      `<div class="cb"><span class="lang">${esc(m[1])}</span><button type="button" class="btn" data-copy>Copy</button><pre><code>${esc(m[2] || "")}</code></pre></div>`;
    at = m.index + m[0].length;
  }
  return out + inline(t.slice(at));
}

if (typeof document !== "undefined") {
  if (!document.querySelector('link[href="/static/css/chat-text.css"]')) {
    const l = document.createElement("link");
    l.rel = "stylesheet"; l.href = "/static/css/chat-text.css";
    document.head.appendChild(l);
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest && e.target.closest(".cb [data-copy]");
    if (b) copied(b, copyText(b.parentNode.querySelector("pre").textContent));
  });
}

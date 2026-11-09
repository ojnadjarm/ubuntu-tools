/* Chat attachments in the stream: an image is its thumbnail linking to the full size, any other file a chip that downloads. */
import { esc } from "/static/js/core/fmt.js";

/* Bytes in his units: B, KB, MB. */
export function size(n) {
  if (n < 1024) return n + " B";
  if (n < 1048576) return Math.round(n / 1024) + " KB";
  return (n / 1048576).toFixed(1).replace(/\.0$/, "") + " MB";
}

/* The attachment row of one message, or "" when it carries none. */
export function attachments(files) {
  if (!files || !files.length) return "";
  return `<div class="atts">${files.map((f) => {
    const url = "/api/chat/file/" + encodeURIComponent(f.id);
    return f.mime.startsWith("image/")
      ? `<a class="att img" href="${url}" target="_blank" rel="noopener"><img src="${url}?thumb=1" alt="${esc(f.name)}" loading="lazy"></a>`
      : `<a class="att file" href="${url}" download="${esc(f.name)}"><span class="nm">${esc(f.name)}</span><span class="sz">${size(f.size)}</span></a>`;
  }).join("")}</div>`;
}

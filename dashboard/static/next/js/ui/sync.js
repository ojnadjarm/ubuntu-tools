/* Morphs live DOM into fresh HTML in place: equal nodes stay, changed text and attributes are patched, so focus, hover light and running animations survive. */
const tpl = document.createElement("template");

/* Children of parent from index skip on become those of html; returns the elements whose [data-dec] text changed. */
export function sync(parent, html, skip = 0) {
  tpl.innerHTML = html;
  const changed = [];
  kids(parent, tpl.content, skip, changed);
  return changed;
}
function kids(a, b, skip, changed) {
  const A = [...a.childNodes].slice(skip), B = [...b.childNodes];
  if (A.length !== B.length) { A.forEach((x) => x.remove()); a.append(...B); return; }
  for (let i = 0; i < A.length; i++) node(a, A[i], B[i], changed);
}
function node(parent, x, y, changed) {
  if (x.nodeType !== y.nodeType || x.nodeName !== y.nodeName) { parent.replaceChild(y, x); return; }
  if (x.nodeType === 3) { if (x.nodeValue !== y.nodeValue) x.nodeValue = y.nodeValue; return; }
  if (x.nodeType !== 1 || x.isEqualNode(y)) return;
  if (x.dataset.decoding) { parent.replaceChild(y, x); return; }
  if (x.hasAttribute("data-dec") && x.textContent !== y.textContent) changed.push(x);
  for (const { name, value } of [...y.attributes]) if (x.getAttribute(name) !== value) x.setAttribute(name, value);
  for (const { name } of [...x.attributes]) if (!y.hasAttribute(name) && name !== "style") x.removeAttribute(name);
  kids(x, y, 0, changed);
}

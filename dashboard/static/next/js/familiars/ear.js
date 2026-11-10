/* Hears new chat messages for a screen that has no chat feed of its own: one read of what is newer every POLL_MS while the screen is on and the page visible. */
import { getJSON } from "/static/js/core/api.js";
import { heard } from "./talk.js";

const POLL_MS = 3000;
let last = null, busy = false, timer = 0;

/* Starts the reads if they are not running; on() says whether the screen is still shown. The first read only marks where "new" begins. */
export function listen(on) {
  if (busy || timer) return;
  busy = true;
  getJSON("/api/chat?recent=1" + (last == null ? "" : "&after=" + last))
    .then((j) => {
      const M = j.messages || [];
      if (last != null) heard(M);
      last = M.length ? M[M.length - 1].id : last || 0;
    }, () => {})
    .finally(() => {
      busy = false;
      if (!on() || document.hidden) { last = null; return; }
      timer = setTimeout(() => { timer = 0; if (on() && !document.hidden) listen(on); else last = null; }, POLL_MS);
    });
}

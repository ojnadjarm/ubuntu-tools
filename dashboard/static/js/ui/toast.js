/* One toast at a time at the foot of the screen: a message, an optional action button, gone after o.ms. */
import {esc} from "../core/fmt.js";
var el=null,tm=0;
/* o: {action, run, ms} */
export function toast(msg,o){o=o||{};hide();var ms=o.ms||4000,t=document.createElement("div");
  t.className="toast";t.setAttribute("role","status");t.style.setProperty("--ms",ms+"ms");
  t.innerHTML='<span>'+esc(msg)+'</span>'+(o.action?'<button class="btn gold" type="button">'+esc(o.action)+'</button>':'');
  t.addEventListener("click",function(e){e.stopPropagation();if(e.target.closest("button")){hide();o.run();}});
  document.body.appendChild(t);el=t;tm=setTimeout(hide,ms);
  requestAnimationFrame(function(){t.classList.add("on");});}
export function hide(){clearTimeout(tm);if(!el)return;var t=el;el=null;t.classList.remove("on");setTimeout(function(){t.remove();},200);}

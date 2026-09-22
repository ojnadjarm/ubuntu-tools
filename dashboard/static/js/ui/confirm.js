/* Destructive-action confirm: a modal that resolves true on the action button, false on Cancel, Esc or a backdrop tap. */
import {esc} from "../core/fmt.js";
var n=0;
/* o: {title, item, body, action} */
export function ask(o){return new Promise(function(done){
  var from=document.activeElement,sel=keyOf(from),id="cfm"+(++n),el=document.createElement("div");
  el.className="cfm";
  el.innerHTML='<div class="card" role="alertdialog" aria-modal="true" aria-labelledby="'+id+'t" aria-describedby="'+id+'d">'
    +'<span class="k">confirm</span><h2 id="'+id+'t">'+esc(o.title)+'</h2>'
    +'<div id="'+id+'d"><b>'+esc(o.item)+'</b><p>'+esc(o.body)+'</p></div>'
    +'<div class="acts"><button class="btn ghost" type="button" data-no>Cancel</button><button class="btn danger" type="button" data-yes>'+esc(o.action)+'</button></div></div>';
  var bs=[].slice.call(el.querySelectorAll("button"));
  function close(ok){if(!el.isConnected)return;el.classList.remove("on");setTimeout(function(){el.remove();},200);
    var f=from&&from.isConnected?from:sel&&document.querySelector(sel);if(f&&f.focus)f.focus();done(ok);}
  el.addEventListener("click",function(e){e.stopPropagation();
    if(e.target===el||e.target.closest("[data-no]"))close(false);else if(e.target.closest("[data-yes]"))close(true);});
  el.addEventListener("keydown",function(e){e.stopPropagation();
    if(e.key==="Escape"){e.preventDefault();close(false);}
    else if(e.key==="Tab"){var i=bs.indexOf(document.activeElement);bs[(i+(e.shiftKey?-1:1)+bs.length)%bs.length].focus();e.preventDefault();}});
  document.body.appendChild(el);bs[0].focus();
  requestAnimationFrame(function(){el.classList.add("on");});
});}
/* A selector for the trigger, so focus can find it again after the screen re-rendered it. */
function keyOf(t){if(!t||!t.attributes)return null;
  for(var i=0;i<t.attributes.length;i++){var a=t.attributes[i];if(/^(id|data-)/.test(a.name))return "["+a.name+'="'+a.value.replace(/["\\]/g,"\\$&")+'"]';}
  return null;}

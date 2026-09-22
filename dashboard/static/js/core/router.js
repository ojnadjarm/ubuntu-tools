/* Hash router, screen swap with in-place patching, and the seen badges on the nav. */
import {getJSON,postJSON} from "./api.js";

export var ORDER=["sites","services","files","docs","notes","machine","style"];
export var cur=null;
export var SEEN={};
var S={},O=null,grid=document.getElementById("grid"),board=document.getElementById("board");

/* o: {screens, ready(), keys() raw new-item keys per screen, hash(to), enter(to,force), read() screen from location.hash} */
export function start(o){S=o.screens;O=o;
  getJSON("/api/seen").then(function(j){Object.assign(SEEN,j||{});if(O.ready())go(cur,true);badges();}).catch(function(){});
  window.addEventListener("hashchange",function(){var h=O.read();if(ORDER.indexOf(h)>=0)go(h,h==="notes"&&h===cur);});
  var first=O.read();
  go(ORDER.indexOf(first)>=0?first:"sites");}

export function newKeys(){var k=O.keys();Object.keys(k).forEach(function(s){k[s]=k[s].filter(function(x){return !SEEN[x];});});return k;}
export function markSeen(keys){var ch=false;keys.forEach(function(x){if(!SEEN[x]){SEEN[x]=1;ch=true;}});if(!ch)return;
  postJSON("/api/seen",keys).catch(function(){});
  document.querySelectorAll("[data-new]").forEach(function(el){if(SEEN[el.dataset.new])el.classList.add("seen");});badges();}
export function badges(){var k=newKeys(),n=0;
  Object.keys(k).forEach(function(s){n+=k[s].length;dot(s,k[s].length?(s==="services"&&k[s].some(function(x){return x.slice(0,6)==="strays";})?"vio":"gold"):"none");});
  document.querySelectorAll("[data-go]").forEach(function(b){var m=k[b.dataset.go]?k[b.dataset.go].length:0;b.setAttribute("aria-label",b.querySelector("span").textContent+(m?": "+m+" new":""));});
  var c=document.getElementById("clear");c.hidden=!n;c.textContent="clear "+n;}
function dot(scr,cls){var b=document.querySelector('.spine [data-go="'+scr+'"] i');if(b)b.className=cls;}

export function go(to,force){
  var D=O.ready();
  if(!S[to]||(to===cur&&!force))return;if(cur&&cur!==to&&D)markSeen(newKeys()[cur]||[]);cur=to;
  var html='<h1 class="sr-only">0'+(ORDER.indexOf(to)+1)+' · '+to+'</h1>'+(D?S[to]():'<div class="empty">loading…</div>');
  if(force&&grid.dataset.live&&D)patch(html);
  else{board.classList.remove("on");void board.offsetWidth;grid.innerHTML=html;}
  grid.dataset.live=D?"1":"";if(!force)board.scrollTop=0;board.classList.add("on");
  document.querySelectorAll("[data-go]").forEach(function(b){b.setAttribute("aria-current",b.dataset.go===to?"true":"false");});
  document.getElementById("crumb").textContent="0"+(ORDER.indexOf(to)+1)+" · "+to;
  var want=O.hash(to);if(location.hash!==want)history.replaceState(null,"",want);
  O.enter(to,force);
}
export function focusKey(el){var a=["data-cd","data-tog","data-file","data-full","data-sort","data-close","id"];for(var i=0;i<a.length;i++){var v=el.getAttribute(a[i]);if(v!=null)return "["+a[i]+'="'+v.replace(/"/g,'\\"')+'"]';}return null;}
function patch(html){var t=document.createElement("div");t.innerHTML=html;var nw=[].slice.call(t.children),old=[].slice.call(grid.children);
  var act=document.activeElement,key=act&&grid.contains(act)?focusKey(act):null,pos=key&&act.tagName==="INPUT"?act.selectionStart:null;
  if(nw.length!==old.length)grid.innerHTML=html;
  else nw.forEach(function(el,i){if(el.outerHTML!==old[i].outerHTML){el.classList.add("still");grid.replaceChild(el,old[i]);}});
  if(key&&!grid.contains(act)){var el=grid.querySelector(key);if(el){el.focus();if(pos!=null)try{el.setSelectionRange(pos,pos);}catch(x){}}}}

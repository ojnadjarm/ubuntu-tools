/* Panel boot: lazy screen modules, the data tick, and global click, key and swipe dispatch. */
import {p2} from "./core/fmt.js";
import {getJSON} from "./core/api.js";
import {ORDER,cur,start,go,newKeys,markSeen} from "./core/router.js";
import {poll} from "./core/poll.js";
import {head,staleLine} from "./ui/head.js";
var D=null,FAILED=false,LAST=null,M={},L={},S={};
var grid=document.getElementById("grid"),board=document.getElementById("board");
ORDER.forEach(function(n){S[n]=function(){if(M[n])return M[n].render(grid,D);load(n);return '<div class="empty">loading…</div>';};});
/* Imports a screen module once, then re-renders it if it is still the active screen. */
function load(n){if(L[n])return;L[n]=import("./screens/"+n+".js").then(function(m){M[n]=m;if(cur===n){if(m.enter)m.enter(false);go(n,true);}});}
function keys(){var v=D&&D.verdict||{ok:true,problems:[]},k={sites:[],services:[],files:[],docs:[],notes:[],machine:[]};
  if(D){(D.plans||[]).forEach(function(p){k.docs.push("plan:"+p.url+"@"+p.updated);});
    ((D.drop||{}).files||[]).forEach(function(f){k.files.push("file:"+f.name+"@"+f.mtime);});
    var down=(D.sites||[]).filter(function(s){return s.state==="down";}).map(function(s){return s.name;}),strays=(D.sites||[]).filter(function(s){return s.state==="stray";}).map(function(s){return s.port;}),failed=(D.units||[]).filter(function(u){return u.active==="failed";}).map(function(u){return u.unit;});
    if(down.length)k.sites.push("sites@"+down.join(","));if(strays.length)k.services.push("strays@"+strays.join(","));if(failed.length)k.services.push("failed@"+failed.join(","));if(!v.ok)k.machine.push("machine@"+v.problems.join("|"));(v.asks||[]).forEach(function(a){k.machine.push("ask:"+a.t);});}
  if(M.notes)M.notes.keys(k);
  return k;}
function readHash(){var h=location.hash.slice(1),i=h.indexOf("?"),scr=i<0?h:h.slice(0,i);if(i>=0&&M[scr]&&M[scr].read)M[scr].read(h.slice(i+1));return scr;}
function hash(to){var m=M[to];if(m&&m.hash)return m.hash();return location.hash.indexOf("#"+to+"?")===0?location.hash:"#"+to;}
function enter(to,force){var m=M[to];if(m&&m.enter)m.enter(force);}
function refresh(){if(!cur)return;var m=M[cur];if(m&&m.refresh&&m.refresh())return;go(cur,true);}
document.addEventListener("click",function(e){
  var m=M[cur];if(m&&m.click&&m.click(e))return;
  if(e.target.id==="retry"){tick();return;}
  if(e.target.id==="clear"){var k=newKeys(),all=[];Object.keys(k).forEach(function(s){all=all.concat(k[s]);});markSeen(all);return;}
  var b=e.target.closest("[data-go]");if(b){go(b.dataset.go);return;}
  var evl=e.target.closest(".ev");if(evl){evl.classList.toggle("open");return;}
  var a=e.target.closest("a[href='#']");if(a)e.preventDefault();
});
document.addEventListener("keydown",function(e){
  if(e.key==="Escape"&&(e.target.id==="fq"||e.target.id==="nq")){e.preventDefault();e.target.blur();return;}
  if(e.metaKey||e.ctrlKey||e.altKey||/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName))return;
  var i=ORDER.indexOf(cur),k=e.key,m=M[cur];
  if(m&&m.key&&m.key(e))return;
  if(k>="1"&&k<="7"){go(ORDER[+k-1]);e.preventDefault();}
  else if(k==="8"){location.href=document.querySelector("[data-voice]").href;e.preventDefault();}
  else if(k==="ArrowRight"&&i<ORDER.length-1){go(ORDER[i+1]);e.preventDefault();}
  else if(k==="ArrowLeft"&&i>0){go(ORDER[i-1]);e.preventDefault();}
  else if(k==="Escape")go("sites");
});
document.addEventListener("input",function(e){var m=M[cur];if(m&&m.input)m.input(e);});
var tx=null,ty=0;
board.addEventListener("touchstart",function(e){var t=e.changedTouches[0];tx=t.clientX;ty=t.clientY;},{passive:true});
board.addEventListener("touchend",function(e){if(tx===null)return;var t=e.changedTouches[0],dx=t.clientX-tx,dy=t.clientY-ty;tx=null;if(Math.abs(dx)<60||Math.abs(dx)<Math.abs(dy))return;var i=ORDER.indexOf(cur)+(dx<0?1:-1);if(i>=0&&i<ORDER.length)go(ORDER[i]);},{passive:true});
function clock(){var d=new Date();document.getElementById("clk").textContent=p2(d.getHours())+":"+p2(d.getMinutes())+":"+p2(d.getSeconds());}
/* Fetches /api/status, redraws the header and refreshes the active screen. */
function tick(){
  var r=document.querySelector(".refresh");r.style.animation="none";void r.offsetWidth;r.style.animation="";
  return getJSON("/api/status").then(function(d){D=d;FAILED=false;LAST=d.now;head(D,FAILED,LAST);refresh();})
  .catch(function(e){console.error(e);FAILED=true;var vd=document.getElementById("verdict");vd.className="ok bad";vd.textContent="unknown";
    if(D)staleLine(LAST);else grid.innerHTML='<div class="empty">panel API not answering · retrying in 30 s</div><div class="btns"><button class="btn gold" id="retry">retry</button></div>';});
}
start({screens:S,ready:function(){return !!D;},keys:keys,read:readHash,enter:enter,hash:hash});
poll(tick,clock);

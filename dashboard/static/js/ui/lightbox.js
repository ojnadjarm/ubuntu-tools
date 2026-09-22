/* Fullscreen image/video viewer: fit or 100 % zoom, drag to pan, swipe and arrows to step through the folder. */
import {esc} from "../core/fmt.js";
import {focusKey} from "../core/router.js";
var lbList=null;
var LB=null,lbIdx=-1,lbFrom=null,lbZ=1,lbX=0,lbY=0,lbFit=true,lbDrag=null;
function lbShow(){var L=lbList(),f=L[lbIdx],src="/files/"+f.path.split("/").map(encodeURIComponent).join("/");lbFit=true;
  LB.querySelector(".m").innerHTML=f.kind==="video"?'<video src="'+src+'" controls autoplay muted playsinline></video>':'<img src="'+src+'" alt="'+esc(f.name)+'" decoding="async" draggable="false">';
  var im=LB.querySelector("img");if(im){if(im.complete&&im.naturalWidth)lbLayout();else im.addEventListener("load",lbLayout);}
  LB.querySelector(".z").hidden=!im;LB.querySelector(".nm").textContent=(lbIdx+1)+" / "+L.length+" · "+f.name;}
function lbLayout(){var im=LB&&LB.querySelector("img");if(!im||!im.naturalWidth)return;var W=LB.clientWidth,H=LB.clientHeight;
  lbZ=lbFit?Math.min(W/im.naturalWidth,H/im.naturalHeight):1;lbX=(W-im.naturalWidth*lbZ)/2;lbY=(H-im.naturalHeight*lbZ)/2;lbApply();}
function lbApply(){var im=LB&&LB.querySelector("img");if(!im)return;var W=LB.clientWidth,H=LB.clientHeight,w=im.naturalWidth*lbZ,h=im.naturalHeight*lbZ;
  lbX=w<=W?(W-w)/2:Math.min(0,Math.max(W-w,lbX));lbY=h<=H?(H-h)/2:Math.min(0,Math.max(H-h,lbY));
  im.style.transform="translate("+lbX+"px,"+lbY+"px) scale("+lbZ+")";im.classList.toggle("pan",w>W||h>H);
  LB.querySelector(".z").textContent=lbFit?"fit · "+Math.round(lbZ*100)+"%":"100%";}
export function open(list,path,from){lbList=list;var L=lbList(),i=-1;L.forEach(function(f,j){if(f.path===path)i=j;});if(i<0)return;lbIdx=i;lbFrom=from?focusKey(from):null;
  if(!LB){LB=document.createElement("div");LB.className="lb";LB.tabIndex=-1;LB.setAttribute("role","dialog");LB.setAttribute("aria-modal","true");LB.setAttribute("aria-label","fullscreen viewer");
    LB.innerHTML='<div class="m"></div><button class="prev" data-lb="-1" aria-label="previous">‹</button><button class="next" data-lb="1" aria-label="next">›</button><div class="top"><button class="z" data-lb="z">fit</button><button data-lb="fs">screen ⤢</button><button data-lb="x">close · esc</button></div><div class="nm"></div>';
    document.body.appendChild(LB);
    LB.addEventListener("pointerdown",function(e){var im=e.target.closest("img");if(!im)return;lbDrag={x:e.clientX,y:e.clientY,ox:lbX,oy:lbY,moved:false};im.setPointerCapture(e.pointerId);e.preventDefault();});
    LB.addEventListener("pointermove",function(e){if(!lbDrag)return;var dx=e.clientX-lbDrag.x,dy=e.clientY-lbDrag.y;if(Math.abs(dx)+Math.abs(dy)>4)lbDrag.moved=true;lbX=lbDrag.ox+dx;lbY=lbDrag.oy+dy;lbApply();});
    LB.addEventListener("pointerup",function(){lbDrag=null;});LB.addEventListener("pointercancel",function(){lbDrag=null;});
    LB.addEventListener("dblclick",function(e){if(e.target.closest("img"))lbZoom();});
    LB.addEventListener("keydown",function(e){if(e.key!=="Tab")return;var bs=[].slice.call(LB.querySelectorAll("button:not([hidden])")),n=bs.length,i=bs.indexOf(document.activeElement);bs[(i+(e.shiftKey?-1:1)+n)%n].focus();e.preventDefault();});
    var sx=null,sy=0;
    LB.addEventListener("touchstart",function(e){var t=e.changedTouches[0];sx=t.clientX;sy=t.clientY;},{passive:true});
    LB.addEventListener("touchend",function(e){if(sx===null||!LB)return;var t=e.changedTouches[0],dx=t.clientX-sx,dy=t.clientY-sy;sx=null;var im=LB.querySelector("img");if(im&&im.classList.contains("pan"))return;if(Math.abs(dx)<60||Math.abs(dx)<Math.abs(dy))return;lbStep(dx<0?1:-1);},{passive:true});}
  lbShow();LB.focus();requestAnimationFrame(function(){if(LB)LB.classList.add("on");});}
function lbZoom(){lbFit=!lbFit;lbLayout();}
function lbClose(){if(!LB)return;var el=LB,back=lbFrom;LB=null;lbFrom=null;if(document.fullscreenElement)document.exitFullscreen().catch(function(){});
  el.classList.remove("on");setTimeout(function(){el.remove();},220);var f=back&&(document.querySelector("button"+back)||document.querySelector(back));if(f)f.focus();}
function nearArrow(x,y){return [].slice.call(LB.querySelectorAll(".prev,.next")).some(function(b){var r=b.getBoundingClientRect();return x>=r.left-44&&x<=r.right+44&&y>=r.top-44&&y<=r.bottom+44;});}
function lbStep(d){var n=lbList().length;if(!n)return;lbIdx=(lbIdx+d+n)%n;lbShow();}
function lbScreen(){if(!LB)return;if(document.fullscreenElement)document.exitFullscreen().catch(function(){});else if(LB.requestFullscreen)LB.requestFullscreen().catch(function(){});}
window.addEventListener("resize",function(){if(LB)lbLayout();});document.addEventListener("fullscreenchange",function(){if(LB)lbLayout();});
export function isOpen(){return !!LB;}
export function key(e){var k=e.key;if(k==="Escape")lbClose();else if(k==="ArrowLeft")lbStep(-1);else if(k==="ArrowRight")lbStep(1);else return;e.preventDefault();}
export function click(e){var lb=e.target.closest("[data-lb]");if(lb){var op=lb.dataset.lb;if(op==="x")lbClose();else if(op==="z")lbZoom();else if(op==="fs")lbScreen();else lbStep(+op);return true;}
  if(LB&&e.target.closest(".lb")){if(e.target.closest(".m")&&!e.target.closest("img,video")&&!nearArrow(e.clientX,e.clientY))lbClose();return true;}}

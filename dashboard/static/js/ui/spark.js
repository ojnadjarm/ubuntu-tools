/* 30-minute sparkline cell, shared by the Machine screen and the style guide. */
import {esc} from "../core/fmt.js";
export function spark(v,label,valTxt){v=v||[];if(v.length<2)return '<div class="sparkc"><div class="lbl"><span class="k">'+label+'</span><b>—</b></div></div>';
  var max=Math.max.apply(null,v)||1,W=100,H=44;var pts=v.map(function(x,i){return (i/(v.length-1)*W).toFixed(1)+","+(H-2-(x/max)*(H-4)).toFixed(1);});
  return '<div class="sparkc"><div class="lbl"><span class="k">'+label+'</span><b>'+esc(valTxt)+'</b></div><svg viewBox="0 0 100 44" preserveAspectRatio="none" role="img" aria-label="'+esc(label)+', last 30 min, now '+esc(valTxt)+'"><polygon points="0,44 '+pts.join(" ")+' 100,44"/><polyline points="'+pts.join(" ")+'"/></svg></div>';}

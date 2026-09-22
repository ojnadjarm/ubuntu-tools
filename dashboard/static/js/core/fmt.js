/* Pure formatting helpers and HTML fragments shared by every screen. */
export var esc=function(s){return String(s==null?"":s).replace(/[&<>"]/g,function(c){return{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];});};
export var pill=function(s,t){return '<span class="pill '+esc(s)+'"><span class="sr-only">state: </span>'+esc(t||s)+'</span>';};

export function size(b){if(b==null)return"";if(b<1024)return b+" B";if(b<1048576)return (b/1024).toFixed(0)+" KB";if(b<1073741824)return (b/1048576).toFixed(1)+" MB";return (b/1073741824).toFixed(1)+" GB";}
export function p2(n){return String(n).padStart(2,"0");}
export function hhmm(iso){if(!iso)return"—";var d=new Date(iso);if(isNaN(d))return iso;return p2(d.getHours())+":"+p2(d.getMinutes());}
export function when(ts){if(!ts)return"—";var d=typeof ts==="number"?new Date(ts*1000):new Date(ts);if(isNaN(d))return String(ts);
  var now=new Date(),day=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()],yd=new Date(now-86400e3);
  if(d.toDateString()===now.toDateString())return hhmm(d.toISOString());
  if(d.toDateString()===yd.toDateString())return "yesterday "+hhmm(d.toISOString());
  if(Math.abs(now-d)<6*86400e3)return day+" "+hhmm(d.toISOString());
  return d.getDate()+" "+["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][d.getMonth()]+(d.getFullYear()===now.getFullYear()?"":" "+d.getFullYear());}
export function ago(iso){if(!iso)return"";var s=(Date.now()-new Date(iso))/1000;if(isNaN(s))return"";
  if(s<3600)return Math.max(0,Math.round(s/60))+" min";if(s<172800)return Math.round(s/3600)+" h";return Math.round(s/86400)+" d";}
export function gb(s){return String(s||"").replace(/(\d+(?:\.\d+)?)([KMGT])\b/g,"$1 $2B");}
export function num(s){var m=/-?\d+(\.\d+)?/.exec(s||"");return m?parseFloat(m[0]):NaN;}

export function glabel(k,v,unit){return (k+" "+v+" "+String(unit).replace(/^·\s*/,"").replace(/^%(?=\s*·|$)/,"% used").replace(/\s*·\s*/g,", ").replace(/^\/ (\d+)$/,"of $1 up")).replace(/\s+/g," ").trim();}
export function gauge(k,v,unit,pct,bad){var C=2*Math.PI*16,p=Math.max(0,Math.min(100,pct||0));
  return '<div class="gauge'+(bad?' bad':'')+'" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+Math.round(p)+'" aria-label="'+esc(glabel(k,v,unit))+'"><svg viewBox="0 0 40 40" aria-hidden="true"><circle class="tr" cx="20" cy="20" r="16"/><circle class="v" cx="20" cy="20" r="16" stroke-dasharray="'+(C*p/100).toFixed(1)+' '+C.toFixed(1)+'"/></svg><span class="k">'+k+'</span><b>'+esc(v)+'<u> '+esc(unit)+'</u></b></div>';}

export function cell(cls,title,right,body,i){return '<section class="cell '+cls+'" style="--i:'+i+'"><h2>'+title+(right||"")+'</h2><div class="body">'+body+'</div></section>';}
export function table(head,rows,empty){if(!rows)return '<div class="empty">'+(empty||"nothing.")+'</div>';
  rows=rows.replace(/<td class="w">([^<]*)<\/td>/g,'<td class="w"><span>$1</span></td>');
  return '<div class="tw"><table><thead><tr>'+head.map(function(h){return '<th class="'+(h[1]||"")+'">'+h[0]+'</th>';}).join("")+'</tr></thead><tbody>'+rows+'</tbody></table></div>';}
export function stat(k,v,cls,meter){return '<div class="stat"><span>'+k+'</span><b class="'+(cls||"")+'">'+v+'</b>'+(meter!=null?'<div class="meter" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+Math.round(meter)+'" aria-label="'+esc(k)+' '+Math.round(meter)+' %"><i style="--v:'+meter+'%"></i></div>':"")+'</div>';}

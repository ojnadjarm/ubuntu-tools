/* Style screen: the living style guide, generated from /static/eye.css. */
import {esc,gauge,cell,stat} from "../core/fmt.js";
import {cur,go} from "../core/router.js";
import {spark} from "../ui/spark.js";
import {copyText,copied} from "../ui/copy.js";
var CSS=null,loading=false;
var DEMOS={
  "table":'<table><thead><tr><th>container</th><th>state</th><th class="a">up</th></tr></thead><tbody><tr><td class="n">moodle52-app-1</td><td><span class="pill up">up</span></td><td class="a">8 d</td></tr><tr><td class="n">moodle52-db-1</td><td><span class="pill up">up</span></td><td class="a">8 d</td></tr></tbody></table>',
  ".pill":'<div class="sg-inline"><span class="pill up">up</span><span class="pill running">running</span><span class="pill ok">ok</span><span class="pill idle">idle</span><span class="pill disabled">disabled</span><span class="pill down">down</span><span class="pill warn">warn</span><span class="pill new">new</span><span class="pill stray">stray</span></div><small style="color:var(--mute);font-size:10px">mint = alive · grey = quiet · gold = needs you · violet = unowned</small>',
  ".k":'<span class="k">section label</span>',
  ".stat":'<div class="stat"><span>used</span><b>52 %</b><div class="meter"><i style="--v:52%"></i></div></div><div class="stat"><span>backups</span><b class="g">2 dumps · 04:31</b></div><div class="stat"><span>auth</span><b class="gold">none</b></div>',
  ".big":'<div class="big" style="padding-left:0"><b>29.6 <u>GB free of 38</u></b><em>load 0.22 · 54 °C</em></div>',
  ".sparkc":spark([1,2,4,3,6,5,9,4,3,2,1,2],"cpu","2 %"),
  ".ev":'<div class="ev"><span class="t">08:00</span><span class="kd push">push</span><span class="x">1. 12 incidents, all one loop …</span></div><div class="ev"><span class="t">03:04</span><span class="kd incident">incident</span><span class="x">FAIL residue: null sink</span></div>',
  ".empty":'<div class="empty"><b>none.</b> every listener has a roster owner</div>',
  ".dots":'<div class="dots" style="padding-left:0"><span class="dot">sentinel</span><span class="dot">keeper</span><span class="dot off">pcbench</span><span class="dot bad">digest</span></div>',
  ".btn":'<div class="sg-inline"><a class="btn" href="#">primary</a><a class="btn ghost" href="#">ghost</a><a class="btn gold" href="#">secondary</a><a class="btn danger" href="#">danger</a></div>',
  ".thumbs":'<div class="thumbs" style="max-width:320px"><div class="thumb open"><div class="im"></div><div class="nm">frame-0412.png</div><div class="sz">148 KB</div></div><div class="thumb"><div class="im"></div><div class="nm">halo-390.png</div><div class="sz">212 KB</div></div></div>',
  ".facets":'<div class="facets" style="border:0"><span class="k">status</span><button class="facet on">active<s>12</s></button><button class="facet">reference<s>17</s></button><span class="k">tag</span><button class="facet">#research<s>1</s></button></div>',
  ".links":'<div class="links" style="max-width:320px"><span class="k">linked from (2)</span><a href="#"><em>Profile — Who I Am</em><s>see [[ai-avatars]] invariants</s></a><a href="#"><em>Quantum Math Prep</em><s>- [[Projects/ai-avatars]] — drops to background during Phase 1</s></a></div>',
  ".viewer":'<div class="viewer" style="padding:0;border:0"><div class="im" style="min-height:60px"></div><div class="meta"><b>file.png</b>image · 148 KB<br>Mon 16:40 · ~/drop</div></div>',
  ".field":'<div class="field"><label>ntfy topic</label><input value="example-topic" readonly aria-label="ntfy topic"><small>≤ 200 characters, no secrets</small></div><div class="field"><label>agent</label><select aria-label="agent"><option>sentinel-check</option><option>moodle-keeper</option></select></div><div class="field err"><label>port</label><input value="80" readonly aria-label="port"><small>▲ below 1024 needs root</small></div>',
  ".linkcard":'<a class="linkcard" href="#">Tonight\'s plan<s>host.tailnet.ts.net:19998/plans/…</s></a>',
  ".page":'<div class="prose"><h3>How the drop folder works</h3><p>Any file you ask for goes in <code>~/drop</code> as a hard link and is served on <a href="#">:8070</a> with a forced download header.</p><blockquote>Say out loud that it is waiting.</blockquote><ul><li>hard link, never a copy</li><li>newest first</li></ul></div>',
  ".sg-*":'<div class="sg-rules"><div><b>this block</b>the guide is drawn with these</div></div>',
  ".board":'<div class="grid" style="grid-template-columns:1fr"><section class="cell"><h2>cell head<s>meta right</s></h2><div class="body"><div class="empty">body · brackets top-left and bottom-right · head on a --w04 wash</div></div></section></div>',
  ".cfm":'<div class="cfm on" style="position:static;background:none;padding:0;place-items:start"><div class="card"><span class="k">confirm</span><h2>Move to trash?</h2><div><b>report-draft.md</b><p>~/drop/report-draft.md leaves the drop; the original file stays.</p></div><div class="acts"><button class="btn ghost" type="button">Cancel</button><button class="btn danger" type="button">Move to trash</button></div></div></div>',
  ".gauge":gauge("disk","9","% · 404 GB free",9)+gauge("battery","72","% health",72)
};
function parseCss(t){
  var root=/:root\s*\{([\s\S]*?)\n\}/.exec(t),tokens=[],m,re=/--([\w-]+):\s*([^;]+);\s*(?:\/\*\s*([\s\S]*?)\s*\*\/)?/g;
  while(root&&(m=re.exec(root[1])))tokens.push({name:"--"+m[1],value:m[2].trim(),what:m[3]||""});
  var hdr=/^\/\*([\s\S]*?)\*\//.exec(t),lines=hdr?hdr[1].split("\n"):[],type=[],space=[],rules=[];
  lines.forEach(function(l){l=l.trim();var a;
    if((a=/^@type\s+(\S+)\s+(.+?)\s+—\s+(.+)$/.exec(l)))type.push({name:a[1],spec:a[2],what:a[3]});
    else if((a=/^@space\s+(.+)$/.exec(l)))space=a[1].split(/\s+/).map(Number);
    else if((a=/^@rule\s+(.+?)\s+—\s+(.+)$/.exec(l)))rules.push({name:a[1],text:a[2]});});
  var comps=[],rc=/\/\*\s*@component\s+(.+?)\s+—\s+(.+?)\s*\*\//g;
  while((m=rc.exec(t)))comps.push({sel:m[1],what:m[2]});
  return {tokens:tokens,type:type,space:space,rules:rules,comps:comps};
}
var TYPE_CSS={display:"font-size:30px;font-weight:600;letter-spacing:-.03em;color:var(--hi);line-height:1",h1:"font-size:20px;font-weight:600;letter-spacing:-.01em;color:var(--hi)",h3:"font-size:13.5px;font-weight:600;color:var(--hi)",body:"font-size:12px;color:var(--txt)",small:"font-size:11px;color:var(--mid)",label:"font-size:10px;letter-spacing:.16em;text-transform:uppercase;color:var(--g)",rail:"font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:var(--mute);font-variant-numeric:tabular-nums"};
var TYPE_TXT={display:"29.6 GB free",h1:"Screen title",h3:"Card heading",body:"Body text sits at 12 px on a 1.5 line, never lighter than --txt.",small:"Secondary text: descriptions, what a thing is.",label:"section label",rail:"rail · 22:14:07 · screen 06/06"};
export function render(){
  if(!CSS)return cell("wide","style","",'<div class="empty">reading /static/eye.css…</div>',0);
  var colors=CSS.tokens.filter(function(t){return /^(#|rgba?)/.test(t.value);}),others=CSS.tokens.filter(function(t){return !/^(#|rgba?)/.test(t.value);});
  var sw='<div class="sg-sw">'+colors.map(function(t){return '<div><i style="--c:'+esc(t.value)+'"></i><s>'+esc(t.name)+'</s><b>'+esc(t.value)+'</b><em>'+esc(t.what)+'</em></div>';}).join("")+'</div>';
  var oth=others.map(function(t){return stat(esc(t.name),'<span style="color:var(--txt)">'+esc(t.value)+'</span> <span class="k">'+esc(t.what)+'</span>');}).join("");
  var ty='<div class="sg-type">'+CSS.type.map(function(t){return '<div><span style="'+(TYPE_CSS[t.name]||"")+'">'+esc(TYPE_TXT[t.name]||t.what)+'</span><code><b>'+esc(t.name)+'</b>'+esc(t.spec)+' · '+esc(t.what)+'</code></div>';}).join("")
    +'<div><span style="font-size:11px;color:var(--mute)">'+esc((CSS.tokens.filter(function(t){return t.name==="--mono";})[0]||{}).value)+'</span><code><b>family</b>one stack, system monospace, no webfont</code></div></div>';
  var sp='<div class="sg-space">'+CSS.space.map(function(s){return '<div><i style="--s:'+s+'px"></i>'+s+'</div>';}).join("")+'</div><div class="sg-rules"><div><b>inside</b>4 · 6 · 8 · 10 within a row or pill</div><div><b>between</b>12 · 14 between cells and columns</div><div><b>sections</b>18 · 22 · 26 between blocks and around headings</div><div><b>lines</b>1 px hairlines only, --line to --line3; 2 px only for the active marker</div></div>';
  var comps=CSS.comps.map(function(c){var key=c.sel.split(/\s+/)[0],demo=DEMOS[key];
    return '<div class="sg-comp"><code>'+esc(c.sel)+'<em>'+esc(c.what)+'</em></code><div class="demo">'+(demo||'<span class="k">chrome · look at this page</span>')+'</div></div>';}).join("");
  var rules='<div class="sg-rules">'+CSS.rules.map(function(r){return '<div><b>'+esc(r.name)+'</b>'+esc(r.text).replace(/No amber\. No red\./,'<u>No amber. No red.</u>')+'</div>';}).join("")+'</div>';
  return cell("wide","style · the living style guide","<s>generated from /static/eye.css</s>",'<div class="empty">Tokens, type, spacing and every component rendered from the same CSS that draws this board, with its class beside it. Source of truth for every agent and every personal web project.</div><div class="btns"><a class="btn" href="/static/eye.css" target="_blank" rel="noopener">eye.css ↗</a><button class="btn gold" data-copy-css>copy tokens as css</button></div>',0)
    +cell("wide","tokens","<s>"+colors.length+" colours · "+others.length+" more</s>",sw+oth,1)
    +cell("two3","type scale","<s>one family</s>",ty,2)
    +cell("third","spacing","<s>px</s>",sp,3)
    +cell("wide","components","<s>"+CSS.comps.length+" · rendered live · class beside</s>",comps,4)
    +cell("wide","rules","<s>the aesthetic in "+CSS.rules.length+" lines</s>",rules,5);
}
export function enter(){
  if(!CSS&&!loading){loading=true;fetch("/static/eye.css",{cache:"force-cache"}).then(function(r){if(!r.ok)throw new Error("http "+r.status);return r.text();}).then(function(t){CSS=parseCss(t);if(cur==="style")go("style",true);},function(){loading=false;});}
}
export function click(e){
  var cc=e.target.closest("[data-copy-css]");if(cc&&CSS){copied(cc,copyText(":root {\n"+CSS.tokens.map(function(t){return "  "+t.name+": "+t.value+";";}).join("\n")+"\n}\n"));return true;}
}

/* Docs screen: pages published under /plans, unread ones marked. */
import {esc,when,cell} from "../core/fmt.js";
import {postJSON} from "../core/api.js";
import {SEEN,go,markSeen} from "../core/router.js";
import {ask} from "../ui/confirm.js";
var D=null;
export function render(grid,d){D=d;
  var pl=D.plans||[];
  var unread=pl.filter(function(p){return !SEEN["plan:"+p.url+"@"+p.updated];}).length;
  var sp={2:spans(pl.length,2),3:spans(pl.length,3)};
  var rows=pl.map(function(x,j){
    var k="plan:"+x.url+"@"+x.updated,fresh=!SEEN[k],mins=Math.max(1,Math.round((x.bytes||0)/1100));
    return '<div class="doc" style="--s2:'+sp[2][j]+';--s3:'+sp[3][j]+'"><a'+(fresh?' class="unread"':"")+' href="'+esc(x.url)+'"><i data-new="'+esc(k)+'"></i>'
      +'<em>'+esc(x.title)+'</em>'
      +'<q>'+esc(x.excerpt||"")+'</q>'
      +'<ol>'+(x.outline||[]).map(function(h){return '<li>'+esc(h)+'</li>';}).join("")+'</ol>'
      +'<s>'+esc(x.kind)+' · '+esc(when(x.updated))+' · '+mins+' min'+(fresh?' · <b>unread</b>':"")+'</s></a><button data-deldoc="'+esc(x.slug)+'" aria-label="delete '+esc(x.title)+'">delete</button></div>';
  }).join("");
  var head='<s>'+pl.length+(pl.length===1?" page":" pages")+(unread?" · "+unread+" unread":"")+'</s>';
  return cell("wide fill","published pages",head,pl.length?'<div class="docs">'+rows+'</div>':'<div class="empty"><b>nothing published yet.</b> plan-publish &lt;file.md&gt;</div>',0);
}
/* Spans on a 6-column grid that fill every row of c columns evenly; the newest cards take the wider rows. */
function spans(n,c){var r=Math.ceil(n/c),base=Math.floor(n/r),out=[];
  for(var row=0;row<r;row++){var k=base+(row>=r-n%r?1:0);for(var j=0;j<k;j++)out.push(6/k);}
  return out;}
export function click(e){
  var db=e.target.closest("[data-deldoc]");if(db){del(db.dataset.deldoc);return true;}
  var pa=e.target.closest('a[href^="/plans/"]');if(pa&&D)markSeen((D.plans||[]).filter(function(p){return p.url===pa.getAttribute("href");}).map(function(p){return "plan:"+p.url+"@"+p.updated;}));
}
function del(slug){var x=(D.plans||[]).filter(function(p){return p.slug===slug;})[0];
  if(!x)return;
  ask({title:"Move to trash?",item:x.title,body:"Its page stops being served; the source file stays.",action:"Move to trash"}).then(function(ok){if(!ok)return;
  postJSON("/api/docs/delete",{slug:slug}).then(function(){D.plans=D.plans.filter(function(p){return p.slug!==slug;});go("docs",true);})
  .catch(function(e){alert("Could not move it to the trash: "+e.message);});});}

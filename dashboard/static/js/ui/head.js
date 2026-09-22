/* Header: gauges, host, verdict and the stale line, redrawn on every tick. */
import {esc,hhmm,gb,num,glabel,gauge} from "../core/fmt.js";
import {badges} from "../core/router.js";
var D=null,FAILED=false,LAST=null;
function sec(n){return ((D.status||{}).sections||{})[n]||{};}
function val(o,k){return ((o||{})[k]||{}).value||"";}
export function head(d,failed,last){D=d;FAILED=failed;LAST=last;
  var pw=sec("power"),res=sec("resources"),host=sec("host"),dk=sec("docker");
  var ram=/(\d+) MB of (\d+) MB/.exec(val(res,"ram_available")),ramPct=ram?100-100*ram[1]/ram[2]:0;
  var diskPct=num(val(res,"disk_root")),load=(val(host,"load")||"").split(" ")[0];
  var up=0,tot=0;Object.keys(dk).forEach(function(k){var m=/(\d+)\/(\d+)/.exec(dk[k].value||"");if(m){up+=+m[1];tot+=+m[2];}});
  var bh=num(val(pw,"battery_health"));
  var G=[["power",num(val(pw,"battery"))||0,"% "+(val(pw,"source")||"").toLowerCase(),num(val(pw,"battery"))],
    ["disk",isNaN(diskPct)?"—":diskPct,"% · "+gb((/,\s*(\S+) free/.exec(val(res,"disk_root"))||[])[1]||"")+" free",diskPct,diskPct>=90],
    ["memory",ram?ramPct.toFixed(0):"—","% · "+(ram?(ram[1]/1024).toFixed(0)+" GB free":""),ramPct,ramPct>=90],
    ["load",load||"—","",Math.min(100,num(load)*12),num(load)*12>=100],
    ["docker",up,"/ "+tot,tot?100*up/tot:0],
    ["battery",isNaN(bh)?"—":bh,"% health",bh,bh<60]];
  var gs=document.querySelectorAll("#gauges .gauge"),C=2*Math.PI*16;
  if(gs.length===6)G.forEach(function(g,i){var p=Math.max(0,Math.min(100,g[3]||0));gs[i].classList.toggle("bad",!!g[4]);
    gs[i].querySelector(".v").setAttribute("stroke-dasharray",(C*p/100).toFixed(1)+" "+C.toFixed(1));gs[i].setAttribute("aria-valuenow",Math.round(p));gs[i].setAttribute("aria-label",glabel(g[0],g[1],g[2]));gs[i].querySelector("b").innerHTML=esc(g[1])+'<u> '+esc(g[2])+'</u>';});
  else document.getElementById("gauges").innerHTML=G.map(function(g){return gauge.apply(null,g);}).join("");
  var h=(D.host||"").split("-").slice(0,2).join("-");
  document.getElementById("host").textContent=D.brand||(D.status&&D.status.sections?(h||D.host):D.host||"machine").toUpperCase();
  document.title=D.brand||h||"panel";
  var v=D.verdict||{ok:true,problems:[]};
  var sok=D.sentinel_last_ok?hhmm(D.sentinel_last_ok):"—";
  document.getElementById("idsub").innerHTML='panel · sentinel <u class="'+(D.sentinel_last_ok&&(Date.now()-new Date(D.sentinel_last_ok))<3600e3?"":"bad")+'">'+(D.sentinel_last_ok?"checked":"unchecked")+'</u> '+esc(sok);
  var unk=FAILED||Object.keys(D.errors||{}).length>0,vd=document.getElementById("verdict");
  vd.className="ok"+(v.ok&&!unk?"":" bad");vd.textContent=unk?"unknown":v.ok?"all clear":v.problems.length+" need you";
  staleLine(FAILED?LAST:(D.stale||[]).length?D.stale_since:null);
  if(D.voice_url)document.querySelectorAll("[data-voice]").forEach(function(a){a.href=D.voice_url;});
  badges();
}
export function staleLine(at){var st=document.getElementById("stale");st.hidden=!at;st.textContent=at?"stale · last "+hhmm(at):"";st.parentNode.classList.toggle("stale",!!at);}

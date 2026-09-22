/* Machine screen: power, disk, memory, network, usage sparklines, docker, failures and events. */
import {esc,pill,when,gb,num,cell,table,stat} from "../core/fmt.js";
import {SEEN} from "../core/router.js";
import {spark} from "../ui/spark.js";
var D=null;
function sec(n){return ((D.status||{}).sections||{})[n]||{};}
function val(o,k){return ((o||{})[k]||{}).value||"";}
export function render(grid,d){D=d;
  var pw=sec("power"),res=sec("resources"),host=sec("host"),net=sec("network"),disk=sec("disk"),v=D.verdict||{ok:true,problems:[]};
  var sp=D.sparks||{},last=function(k){var a=(sp[k]||{}).values||[];return a.length?a[a.length-1]:NaN;};
  var ram=/(\d+) MB of (\d+) MB/.exec(val(res,"ram_available")),ramPct=ram?100-100*ram[1]/ram[2]:0;
  var dock=(D.docker||[]).map(function(x){return '<tr><td class="n">'+esc(x.name)+'</td><td class="w">:'+x.ports.join(" :")+'</td><td>'+pill(x.state)+'</td><td class="a">'+esc(x.status.replace(/^Up /,""))+'</td></tr>';}).join("");
  var ev=(D.events||[]).map(function(e){return '<div class="ev"><span class="t">'+esc(when(e.t))+'</span><span class="kd '+esc(e.kind)+'">'+esc(e.kind)+'</span><span class="x">'+esc(e.text)+'</span></div>';}).join("");
  var ag=(D.agents||[]).map(function(a){var ex=a.last&&a.last.exit;return '<span class="dot '+(ex==null||ex===""?"off":ex==="0"?"":"bad")+'" title="'+esc(a.last&&a.last.end||"never ran")+'">'+esc(a.name)+'</span>';}).join("");
  var fails=(v.asks||[]).map(function(a){var k="ask:"+a.t;return '<div class="ev open"><span class="t">'+esc(when(a.t))+'</span><span class="kd push">ask</span><span class="x">'+esc(a.text)+(SEEN[k]?"":' <span class="pill new" data-new="'+esc(k)+'">new</span>')+'</span></div>';}).join("")
    +Object.keys(D.errors||{}).map(function(k){return '<div class="ev"><span class="t">now</span><span class="kd warn">error</span><span class="x">'+esc(k)+' collector: '+esc(D.errors[k])+'</span></div>';}).join("")
    +v.problems.filter(function(p){return p.slice(0,4)!=="ask:";}).map(function(p){return '<div class="ev"><span class="t">now</span><span class="kd warn">fail</span><span class="x">'+esc(p)+'</span></div>';}).join("");
  var nf=v.problems.length+Object.keys(D.errors||{}).length;
  var diskPct=num(val(res,"disk_root"));
  return cell("q","power",pill((sec("power").battery||{}).state==="FAIL"?"warn":"ok"),'<div class="big"><b>'+esc(val(pw,"source")||"—")+' <u>'+esc(val(pw,"battery"))+'</u></b><em>lid '+esc(val(pw,"lid")||"?")+' · health '+esc((val(pw,"battery_health")||"").split(" of")[0])+'</em></div>'+stat("profile",esc(val(pw,"profile")||"—"),"",num(val(pw,"battery"))),0)
    +cell("q","disk",pill(val(disk,"smart")==="PASSED"?"ok":"warn"),'<div class="big"><b>'+(isNaN(diskPct)?"—":diskPct)+' <u>% · '+esc(gb((/,\s*(.+)$/.exec(val(res,"disk_root"))||[])[1]||""))+'</u></b><em>'+(val(disk,"smart")==="PASSED"?"disk healthy":"disk "+esc((val(disk,"smart")||"unknown").toLowerCase()))+' · '+esc((val(disk,"percent_used")||"?").replace("%"," %"))+' worn</em></div>'+stat("spare",esc(val(disk,"available_spare")||"—"),"",diskPct),1)
    +cell("q","memory · cpu",pill("ok"),'<div class="big"><b>'+(ram?(ram[1]/1024).toFixed(1):"—")+' <u>GB free of '+(ram?(ram[2]/1024).toFixed(0):"—")+'</u></b><em>load '+esc(val(host,"load"))+' · '+esc(val(res,"temp_max")).replace(" C"," °C")+'</em></div>'+stat("used",ramPct.toFixed(0)+" %","",ramPct),2)
    +cell("q","network",pill(val(net,"tailscale")==="Running"?"ok":"warn"),'<div class="big"><b>tailscale <u>'+(val(net,"tailscale")==="Running"?"on":esc((val(net,"tailscale")||"?").toLowerCase()))+'</u></b><em>'+esc(val(net,"wifi_ssid")||"no wifi")+' · internet '+esc(val(net,"internet")||"?")+'</em></div>'+stat("lan · tailscale",esc(val(net,"lan_ip"))+" · "+esc(val(net,"tailscale_ip"))),3)
    +cell("wide","usage","<s>last 30 min</s>",'<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr))">'+spark((sp.cpu||{}).values,"cpu",isNaN(last("cpu"))?"—":last("cpu").toFixed(0)+" %")+spark((sp.ram||{}).values,"ram",isNaN(last("ram"))?"—":last("ram").toFixed(0)+" %")+spark((sp.io||{}).values,"io",isNaN(last("io"))?"—":last("io").toFixed(0)+" KB/s")+spark((sp.net||{}).values,"net",isNaN(last("net"))?"—":last("net").toFixed(0)+" kbit/s")+'</div>',4)
    +cell("half","docker","<s>"+(D.docker||[]).filter(function(c){return c.state==="running";}).length+" of "+(D.docker||[]).length+" up</s>",table([["container"],["ports","w"],["state"],["up","a"]],dock,"docker not reachable"),5)
    +cell("half","failures",(nf?pill("warn",nf):pill("ok","none"))+"<s>now</s>",(nf?fails:'<div class="empty"><b>none.</b> nothing failed, every agent finished clean, no push waits on you.</div>')+'<div class="dots">'+ag+'</div>',6)
    +cell("wide","events","<s>24 h · pushes and incidents</s>",ev||'<div class="empty"><b>quiet.</b> no push, no incident in the last 24 h</div>',7);
}

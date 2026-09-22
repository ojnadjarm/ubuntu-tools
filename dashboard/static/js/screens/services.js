/* Services screen: listening ports, strays, user units and timers. */
import {esc,pill,size,when,ago,cell,table} from "../core/fmt.js";
import {go} from "../core/router.js";
var D=null,showDesk=false,showSys=false;
export function render(grid,d){D=d;
  var sites=D.sites||[],units=D.units||[],timers=D.timers||[];
  var ports=sites.filter(function(s){return !s.group&&s.state!=="stray";}).map(function(p){return '<tr><td class="n">'+esc(p.name)+'</td><td>'+pill(p.state)+'</td><td class="w">'+esc(p.what)+'</td><td class="p">:'+p.port+'</td><td class="u">'+esc(p.unit||p.proc||"")+'</td><td class="a">'+esc(p.uptime)+'</td></tr>';}).join("");
  var strays=sites.filter(function(s){return s.state==="stray";}).map(function(t){return '<tr><td class="p">:'+t.port+'</td><td class="n">'+esc(t.proc||"?")+(t.pid?' <span class="k">pid '+t.pid+'</span>':"")+'</td><td>'+pill("stray")+'</td><td class="w">'+esc(t.unit||"no unit")+'</td><td class="a">'+esc(t.uptime)+'</td></tr>';}).join("");
  var urow=function(u){var st=u.active==="active"?u.sub:u.active;return '<tr><td class="n">'+esc(u.unit.replace(/\.service$/,""))+(u.group==="fleet"?' <span class="k">never stop</span>':"")+'</td><td>'+pill(st)+'</td><td class="w">'+esc(u.what)+'</td><td class="p">'+(u.rss?size(u.rss):"—")+'</td><td class="a">'+esc(u.since?ago(u.since):"")+'</td></tr>';};
  var ucols=[["unit"],["state"],["what","w"],["rss","p"],["up","a"]],grp=function(g){return units.filter(function(u){return u.group===g;});};
  var ugroup=function(g,empty){var rows=grp(g);return '<tr class="grp"><td colspan="5">'+(g==="his"?"yours":g)+' ('+rows.length+')</td></tr>'+(rows.length?rows.map(urow).join(""):'<tr class="grp none"><td colspan="5">'+empty+'</td></tr>');};
  var desk=grp("desktop").length,us=table(ucols,ugroup("fleet","<b>nothing running.</b> the fleet is stopped")+ugroup("his","<b>none.</b> only the fleet and the desktop are running")+(showDesk?ugroup("desktop","<b>none.</b>"):""))
    +(desk?'<div class="btns"><button class="btn ghost" data-desk>'+(showDesk?"− ":"+ ")+desk+' desktop</button></div>':"");
  var sysT=/^(ubuntu-insights-|launchpadlib-|snap\.)/,mine=timers.filter(function(t){return !sysT.test(t.unit);}),sys=timers.length-mine.length;
  var trow=function(t){return '<tr><td class="n">'+esc(t.unit.replace(/\.timer$/,""))+'</td><td class="w">'+esc(t.every||"—")+'</td><td class="a">'+esc(when(t.next))+'</td><td class="u">'+esc(when(t.last))+'</td></tr>';};
  var tm=table([["timer"],["every","w"],["next","a"],["last","u"]],mine.map(trow).join(""))
    +(sys?'<div class="btns"><button class="btn ghost" data-sys>'+(showSys?"− ":"+ ")+sys+' system</button></div>'+(showSys?table([["timer"],["every","w"],["next","a"],["last","u"]],timers.filter(function(t){return sysT.test(t.unit);}).map(trow).join("")):""):"");
  var next=mine.filter(function(t){return t.next;})[0],strayN=sites.filter(function(s){return s.state==="stray";}).length;
  return cell("two3","ports","<s>"+sites.filter(function(s){return !s.group&&s.state!=="stray";}).length+" listeners</s>",table([["service"],["state"],["what","w"],["port","p"],["unit","u"],["up","a"]],ports),0)
    +cell("third","strays",(strays?pill("stray"):pill("ok","none"))+"<s>"+strayN+(strayN===1?" stray":" strays")+"</s>",table([["port","p"],["proc"],["state"],["unit","w"],["age","a"]],strays,"<b>none.</b> every listener has a roster owner")+'<div class="empty">a stray is a listener with no roster owner — usually a dev server left running</div>',1)
    +cell("half","services","<s>"+(units.length-desk)+" running · "+desk+" desktop</s>",us,2)
    +cell("half","timers","<s>"+mine.length+" timers"+(next?" · next "+esc(when(next.next)):"")+"</s>",tm,3);
}
export function click(e){
  if(e.target.closest("[data-desk]")){showDesk=!showDesk;go("services",true);return true;}
  if(e.target.closest("[data-sys]")){showSys=!showSys;go("services",true);return true;}
}

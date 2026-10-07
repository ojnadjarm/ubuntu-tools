/* Sites screen: the project tiles, then every web site on this machine, grouped mine / moodle / metrics. */
import {esc,pill,cell,table,stat,when,ago} from "../core/fmt.js";
function link(u,label){var m=/^https?:\/\/([^.:\/]+)[^:\/]*(:\d+)?/.exec(u);return '<a href="'+esc(u)+'" target="_blank" rel="noopener">'+esc(label||(m?m[1]+(m[2]||""):u))+'</a>';}
function project(p,i){
  var n=p.containers.length,code=p.site_code==null?"no answer":p.site_code;
  var st=stat("containers",p.containers.map(function(c){return esc(c.name.replace(/^[^-]+-|-\d+$/g,""))+" "+esc(c.state);}).join(" · ")||"none",p.up===n&&n?"g":"gold")
    +stat("site",esc(code),p.site_code===200?"g":"gold")+stat("https",link(p.https)+(p.frontend?" · "+link(p.frontend,"Frontend"):""))+stat("http",link(p.http))+stat("mailhog",link(p.mailhog))
    +stat("login",esc(p.login))+stat("db",esc(p.db))+stat("folder",esc(p.folder))+stat("repo",esc(p.repo))
    +stat("last commit",p.commit_at?'<span title="'+esc(p.commit)+'">'+esc(when(p.commit_at))+" · "+esc(ago(p.commit_at))+" ago</span>":"unreadable")
    +stat("worktree",p.dirty==null?"unreadable":p.dirty?p.dirty+" changed":"clean",p.dirty?"gold":"g")
    +stat("todo · tickets",(p.todo==null?"no Todo section":p.todo+" open")+" · "+(p.tickets==null?"no TICKETS.md":'<a href="'+esc(p.tickets_url)+'">Tickets</a> '+p.tickets+" pending"),p.todo||p.tickets?"gold":"");
  return cell("wide","project · "+esc(p.name),pill(p.state)+"<s>"+p.up+"/"+n+" up · site "+esc(code)+"</s>",
    '<div class="big"><b>'+esc(p.name)+'</b><em>'+esc(p.what)+'</em></div><div class="proj">'+st+'</div>',i);
}
export function render(grid,D){
  var sites=D.sites||[],groups=[["mine","wide"],["moodle","half roomy"],["metrics","half roomy"]],i=0,h="";
  (D.projects||[]).forEach(function(p){h+=project(p,i++);});
  groups.forEach(function(g){
    var list=sites.filter(function(s){return s.group===g[0];});
    if(g[0]==="mine"&&D.voice_url){var dash=sites.filter(function(s){return s.port===19998;})[0]||{};list=list.concat([{name:"Voice training",what:"read prompts aloud so the Eye learns your voice · open the https link, the mic needs it",url:D.voice_url,state:dash.state||"up",uptime:"",tls:true}]);}
    var rows=list.map(function(s){
      var host=s.host||(s.url?s.url.replace(/^https?:\/\//,"").replace(/\/$/,""):"");
      return '<tr><td class="n">'+(s.url?'<a href="'+esc(s.url)+'" target="_blank" rel="noopener">'+esc(s.name)+'</a>':esc(s.name))+'</td><td class="w">'+esc(s.what)+'</td><td class="u">'+(s.url?'<a href="'+esc(s.url)+'" target="_blank" rel="noopener">'+esc(host)+'</a>':"")+'</td><td>'+pill(s.state)+'</td><td class="a">'+(s.ms!=null?(s.ms<100?s.ms+" ms · ":(s.ms/1000).toFixed(1)+" s · "):"")+esc(s.uptime)+(s.tls?" · https":"")+'</td></tr>';}).join("");
    var n=list.length;
    h+=cell(g[1],"sites · "+g[0],"<s>"+n+(n===1?" site":" sites")+"</s>",table([["name"],["what","w"],["tailnet url","u"],["state"],["up","a"]],rows,"nothing listening"),i++);
  });
  return h;
}

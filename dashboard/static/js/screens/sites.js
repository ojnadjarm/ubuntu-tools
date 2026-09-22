/* Sites screen: every web site on this machine, grouped mine / moodle / metrics. */
import {esc,pill,cell,table} from "../core/fmt.js";
export function render(grid,D){
  var sites=D.sites||[],groups=[["mine","wide"],["moodle","half roomy"],["metrics","half roomy"]],i=0,h="";
  groups.forEach(function(g){
    var list=sites.filter(function(s){return s.group===g[0];});
    if(g[0]==="mine"&&D.voice_url){var dash=sites.filter(function(s){return s.port===19998;})[0]||{};list=list.concat([{name:"Voice training",what:"read prompts aloud so the Eye learns your voice · open the https link, the mic needs it",url:D.voice_url,state:dash.state||"up",uptime:"",tls:true}]);}
    var rows=list.map(function(s){
      var host=s.url?s.url.replace(/^https?:\/\//,"").replace(/\/$/,""):"";
      return '<tr><td class="n">'+(s.url?'<a href="'+esc(s.url)+'" target="_blank" rel="noopener">'+esc(s.name)+'</a>':esc(s.name))+'</td><td class="w">'+esc(s.what)+'</td><td class="u">'+(s.url?'<a href="'+esc(s.url)+'" target="_blank" rel="noopener">'+esc(host)+'</a>':"")+'</td><td>'+pill(s.state)+'</td><td class="a">'+(s.ms!=null?(s.ms<100?s.ms+" ms · ":(s.ms/1000).toFixed(1)+" s · "):"")+esc(s.uptime)+(s.tls?" · https":"")+'</td></tr>';}).join("");
    var n=list.length;
    h+=cell(g[1],"sites · "+g[0],"<s>"+n+(n===1?" site":" sites")+"</s>",table([["name"],["what","w"],["tailnet url","u"],["state"],["up","a"]],rows,"nothing listening"),i++);
  });
  return h;
}

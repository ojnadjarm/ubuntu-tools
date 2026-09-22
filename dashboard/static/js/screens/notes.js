/* Notes screen: today, audio notes, the read-only note viewer, vault search and the vault table. */
import {esc,pill,size,when,cell,table,stat} from "../core/fmt.js";
import {getJSON} from "../core/api.js";
import {cur,go,markSeen,badges} from "../core/router.js";
var D=null,grid=null,N=null,T=null,A=null,openNote=null,noteDoc=null,noteQ="",noteHits=null,noteSort="new",noteFilter={},showLinks=true;
export function render(g,d){grid=g;D=d;
  if(!N)return cell("wide","notes","",'<div class="empty">reading ~/obsidian-vault…</div>',0);
  if(N.error)return cell("wide","notes","",'<div class="empty">vault not readable ('+esc(N.error)+')</div>',0);
  var notes=N.notes||[],facets=N.facets||{folders:{},status:{},tags:{}},i=0;
  var lab=function(x){return x.status?' <span class="k">'+esc(x.status)+'</span>':"";};
  var row=function(x){return '<tr'+(x.path===openNote?' class="sel"':'')+'><td class="n"><a href="#notes" data-note="'+esc(x.path)+'">'+esc(x.title)+'</a>'+lab(x)+'</td><td class="w">'+esc(x.folder)+'</td><td class="p lk">'+(x.links_in||0)+' / '+(x.links_out||0)+'</td><td class="a">'+esc(when(x.mtime))+'</td><td class="p">'+size(x.bytes)+'</td></tr>';};
  var viewer='<div class="empty">tap a note · rendered here, read-only</div>';
  if(openNote){
    var n=notes.filter(function(x){return x.path===openNote;})[0]||{path:openNote,title:openNote},d=noteDoc;
    var fm=d?Object.keys(d.frontmatter).map(function(k){return stat(esc(k),esc(d.frontmatter[k]));}).join(""):"";
    var tags=d&&d.tags.length?'<div class="tags">'+d.tags.map(function(t){return '<span class="tag">'+esc(t)+'</span>';}).join("")+'</div>':"";
    var lk=function(title,arr){return arr&&arr.length?'<div class="links"><span class="k">'+title+' ('+arr.length+')</span>'+arr.map(function(l){return '<a href="#notes" data-note="'+esc(l.path)+'"><em>'+esc(l.title)+'</em><s>'+esc(l.line)+'</s></a>';}).join("")+'</div>':"";};
    var un=d&&d.unresolved&&d.unresolved.length?'<div class="links"><span class="k">unresolved ('+d.unresolved.length+')</span>'+d.unresolved.map(function(t){return '<span class="wl miss" style="display:block">[['+esc(t)+']]</span>';}).join("")+'</div>':"";
    var ol=d&&d.headings&&d.headings.length>1?'<div class="outline"><span class="k">outline</span>'+d.headings.map(function(h){return '<a href="#notes" data-hd="'+esc(h.id)+'" style="--l:'+(h.level-1)+'">'+esc(h.text)+'</a>';}).join("")+'</div>':"";
    var gr=d&&d.neighbours&&d.neighbours.length?lgraph(n,d.neighbours):"";
    var lists=d&&showLinks?lk("linked from",d.links_in)+lk("links to",d.links_out)+un:"";
    viewer='<div class="viewer"><div class="im">'+tags+'<div class="prose" id="ntxt">'+(d?d.html:'<pre>loading…</pre>')+'</div></div><div class="meta"><b>'+esc(n.title)+'</b>'+esc(n.path)+'<br>'+esc(when(n.mtime))+' · '+size(n.bytes)+(fm?'<div style="margin:8px 0 0;border-top:1px solid var(--line)">'+fm+'</div>':"")+ol+gr+lists+'<div class="btns"><button class="btn ghost" data-close-note>close</button>'+(d&&(d.links_in.length||d.links_out.length)?'<button class="btn ghost" data-links>'+(showLinks?"hide":"show")+' links · b</button>':"")+'</div></div></div>';
  }
  var hits=noteHits==null?'<div class="empty">ranked: title, then headings, then body · "exact phrase" · status:active folder:Projects tag:x</div>':noteHits.error?'<div class="empty"><b>search failed.</b></div>':noteHits.count?'<div class="tw"><table><tbody>'+noteHits.hits.map(function(x){return '<tr><td class="n"><a href="#notes" data-note="'+esc(x.path)+'">'+esc(x.title)+'</a>'+lab(x)+'<br><span class="k">'+esc(x.folder)+'</span>'+(x.snippets||[]).map(function(sn){return '<div class="snip">'+sn+'</div>';}).join("")+'</td></tr>';}).join("")+'</tbody></table></div>':'<div class="empty"><b>no match.</b></div>';
  var chips=function(kind,obj,byCount){return Object.keys(obj).sort(byCount?function(a,b){return obj[b]-obj[a]||a.localeCompare(b);}:undefined).map(function(k){return '<button class="facet'+(noteFilter[kind]===k?" on":"")+'" data-facet="'+kind+'" data-v="'+esc(k)+'" aria-pressed="'+(noteFilter[kind]===k)+'">'+(kind==="tag"?"#":"")+esc(k==="/"?"vault root":k)+'<s>'+obj[k]+'</s></button>';}).join("");};
  var fac='<div class="facets"><span class="k">folder</span>'+chips("folder",facets.folders)+'<span class="k">status</span>'+chips("status",facets.status,true)+(Object.keys(facets.tags).length?'<span class="k">tag</span>'+chips("tag",facets.tags,true):"")+'</div>';
  var list=noteList();
  var rows="",lastF=null;list.forEach(function(x){if(noteSort==="tree"&&x.folder!==lastF){lastF=x.folder;rows+='<tr><td colspan="5"><span class="k">'+esc(x.folder==="/"?"vault root":x.folder)+'</span></td></tr>';}rows+=row(x);});
  var filtered=list.length!==notes.length;
  var sort='<button data-sort="new" class="btn'+(noteSort==="new"?"":" ghost")+'" style="margin-left:auto" aria-pressed="'+(noteSort==="new")+'">newest</button><button data-sort="tree" class="btn'+(noteSort==="tree"?"":" ghost")+'" aria-pressed="'+(noteSort==="tree")+'">tree</button>'+(filtered?'<button data-facet="" class="btn gold">clear</button>':"")+'<s>'+(filtered?list.length+' of ':'')+notes.length+' notes · '+size(N.bytes)+'</s>';
  var wanted=(N.unresolved||[]).length?'<div class="links pad"><span class="k">missing notes ('+N.unresolved.length+')</span>'+N.unresolved.map(function(u){return '<a href="#notes" data-note="'+esc(u.from)+'"><em class="miss">[['+esc(u.target)+']]</em><s>from '+esc(u.from)+'</s></a>';}).join("")+'</div>':"";
  return cell("wide","today",T?'<s>'+T.tasks.length+' open tasks · '+esc(T.date)+'</s>':"",todayBody(),i++)
    +cell("wide","audio notes",A?brainHead():"",audioBody(),i++)
    +cell("two3 read","note",'<s>'+(openNote?esc(openNote):"")+'</s>',viewer,i++)
    +cell("third side","search",'<s id="nqs">'+(noteHits&&noteQ?noteHits.count+(noteHits.count===1?' hit':' hits'):"")+'</s>','<div class="pad"><div class="field"><label for="nq">find</label><input id="nq" type="search" placeholder="word or phrase" value="'+esc(noteQ)+'" autocomplete="off"></div></div><div id="nres">'+hits+'</div>',i++)
    +cell("wide","vault",sort,fac+table([["title"],["folder","w"],["links in / out","p lk"],["modified","a"],["size","p"]],rows,"<b>no note</b> matches this filter")+wanted,i++);
}
function noteList(){var list=((N&&N.notes)||[]).filter(noteMatch);if(noteSort==="tree")list.sort(function(a,b){return a.folder===b.folder?a.title.localeCompare(b.title):(a.folder==="/"?"":a.folder).localeCompare(b.folder==="/"?"":b.folder);});return list;}
function todayBody(){if(!T)return '<div class="empty">reading…</div>';
  var nl=function(x,sub){return '<a href="#notes" data-note="'+esc(x.path)+'"><em>'+esc(x.title)+'</em><s>'+sub+'</s></a>';};
  var daily=T.daily?nl({path:T.daily,title:T.date},"today's daily note · open"):'<div class="empty"><b>no daily note</b> yet today'+(T.template?' · from <a href="#notes" data-note="'+esc(T.template)+'">'+esc(T.template.split("/").pop())+'</a> once capture ships':"")+'</div>';
  var recent=T.recent.length?T.recent.map(function(r){return nl(r,esc(when(r.ctime))+(r.line?' · '+esc(r.line):""));}).join(""):'<div class="empty"><b>empty</b> vault</div>';
  var groups=0,last=null,tasks="";T.tasks.forEach(function(t){if(t.path!==last){last=t.path;groups++;tasks+='<a class="gh" href="#notes" data-note="'+esc(t.path)+'">'+esc(t.title)+'<s>'+T.tasks.filter(function(x){return x.path===t.path;}).length+'</s></a>';}tasks+='<a class="tk" href="#notes" data-note="'+esc(t.path)+'" title="line '+t.line+'">'+esc(t.text)+'</a>';});
  return '<div class="today"><div><span class="k">daily · '+esc(T.date)+'</span>'+daily+'</div><div><span class="k">newest files ('+T.recent.length+')</span>'+recent+'</div><div><span class="k">open tasks ('+T.tasks.length+' in '+groups+' notes)</span><div class="tasks">'+(tasks||'<div class="empty"><b>none</b> open</div>')+'</div></div></div>';}
function brainHead(){var u=(D&&D.units||[]).filter(function(x){return x.unit==="notes-brain.service";})[0],on=!!u&&u.active==="active",c=A.brain.connected;
  var att=c===true?"attached to the Eye":c===false?"not attached to the Eye"+(on&&u.since?" since "+when(u.since):""):"attachment unknown";
  return (c===true?pill("up","brain attached"):pill("idle",c===false?"brain not attached":"brain unknown"))+'<s>brain: unit '+(u?(on?"running":esc(u.active)):"not running")+' · '+att+' · '+(A.brain.last_filed?'filed '+esc(when(A.brain.last_filed)):"never filed")+(c===true?"":' · say <u>talk to notes</u>')+'</s>';}
function audioBody(){if(!A)return '<div class="empty">reading…</div>';
  var line=function(x,body){return '<div class="al"><i>'+esc(x.at)+'</i><span>'+body+'</span></div>';};
  var ideas=A.ideas.length?A.ideas.map(function(x){return '<a href="#notes" data-note="'+esc(x.path)+'"><em>'+esc(x.title)+'</em><s>'+esc(when(x.mtime))+(x.tags.length?' · #'+x.tags.join(" #"):"")+'</s></a>';}).join(""):'<div class="empty"><b>no ideas</b> filed yet · they land in '+esc(A.folder)+'/ideas/</div>';
  if(!A.today)return '<div class="audio"><div class="empty"><b>nothing filed today</b>'+(A.brain.last_filed?"":" · never filed since the brain started")+'.<br>say <u>talk to notes</u>, the idea, then <u>file it</u> · the ear writes '+esc(A.folder)+'/'+esc(A.date)+'.md (raw, then refined) and one file per idea.</div><div><span class="k">ideas ('+A.ideas.length+')</span>'+ideas+'</div></div>';
  var raw=A.today.raw.length?A.today.raw.map(function(x){return line(x,esc(x.text));}).join(""):'<div class="empty"><b>nothing</b> heard</div>';
  var ref=A.today.refined.length?A.today.refined.map(function(x){return line(x,(x.path?'<a class="wl" href="#notes" data-note="'+esc(x.path)+'"'+(x.heading?' data-hd="'+esc(x.heading)+'"':"")+'>'+esc(x.file.split("/").pop()+(x.heading?" › "+x.heading:""))+'</a> ':'<span class="wl miss">[['+esc(x.file)+']]</span> ')+esc(x.gist)+(x.sure?"":' <span class="k">(?)</span>'));}).join(""):'<div class="empty"><b>nothing</b> filed yet</div>';
  return '<div class="audio"><div><span class="k">raw · '+A.today.raw.length+' <a href="#notes" data-note="'+esc(A.today.path)+'">'+esc(A.date)+'.md</a></span>'+raw+'</div><div><span class="k">refined · '+A.today.refined.length+'</span>'+ref+'</div><div><span class="k">ideas ('+A.ideas.length+')</span>'+ideas+'</div></div>';}
function lgraph(n,near){var MAX=30,list=near.slice(0,MAX),W=300,H=160,cx=150,cy=80,rx=118,ry=58,out="";
  list.forEach(function(x,i){var a=-Math.PI/2+i*2*Math.PI/list.length,x1=cx+rx*Math.cos(a),y1=cy+ry*Math.sin(a),lab=x.title.length>16?x.title.slice(0,15)+"…":x.title,left=x1<cx-4;
    out+='<line x1="'+cx+'" y1="'+cy+'" x2="'+x1.toFixed(1)+'" y2="'+y1.toFixed(1)+'" class="'+x.dir+'"/><g data-note="'+esc(x.path)+'" role="button" tabindex="0"><circle class="hit" cx="'+x1.toFixed(1)+'" cy="'+y1.toFixed(1)+'" r="12" fill="transparent"/><circle cx="'+x1.toFixed(1)+'" cy="'+y1.toFixed(1)+'" r="3.5"/><text x="'+(x1+(left?-6:6)).toFixed(1)+'" y="'+(y1+3).toFixed(1)+'"'+(left?' text-anchor="end"':"")+'>'+esc(lab)+'</text></g>';});
  out+='<circle cx="'+cx+'" cy="'+cy+'" r="5" class="me"/>';
  return '<div class="lgraph"><span class="k">local graph · '+near.length+(near.length>MAX?' (first '+MAX+' drawn)':'')+'</span><svg viewBox="0 0 '+W+' '+H+'" aria-label="notes linked to '+esc(n.title)+'">'+out+'</svg></div>';}
function noteMatch(x){var f=noteFilter;
  if(f.folder&&x.folder!==f.folder&&x.folder.indexOf(f.folder+"/")!==0)return false;
  if(f.status&&(x.status||"")!==f.status)return false;
  if(f.tag&&(x.tags||[]).indexOf(f.tag)<0)return false;return true;}
export function hash(){var q=Object.keys(noteFilter).filter(function(k){return noteFilter[k];}).map(function(k){return k+"="+encodeURIComponent(noteFilter[k]);}).join("&");return "#notes"+(q?"?"+q:"");}
function nfetch(u,ok){var re=function(){badges();if(cur==="notes")go("notes",true);};
  return getJSON(u).then(function(j){ok(j);re();}).catch(function(e){N={error:e.message};re();});}
function loadDay(){nfetch("/api/notes/today",function(t){T=t;});nfetch("/api/notes/audio",function(a){A=a;});}
function loadNotes(){nfetch("/api/notes",function(n){N=n;});loadDay();}
function jumpHd(id){var el=document.querySelector('#ntxt [id="'+id+'"]');if(!el){pendingHd=id;return;}pendingHd=null;el.scrollIntoView({block:"start"});}
var pendingHd=null;
function scrollRead(){requestAnimationFrame(function(){var c=grid.querySelector(".cell.read");if(c)c.scrollIntoView({block:"start"});});}
function openNoteDoc(path){openNote=path;noteDoc=null;go("notes",true);scrollRead();
  if(N)markSeen((N.latest||[]).filter(function(n){return n.path===path;}).map(function(n){return "note:"+n.path+"@"+n.mtime;}));
  getJSON("/notes/"+path.split("/").map(encodeURIComponent).join("/"))
  .then(function(d){if(openNote===path){noteDoc=d;go("notes",true);if(pendingHd){var want=pendingHd,hit=(d.headings||[]).filter(function(h){return h.text===want||h.id===want;})[0];pendingHd=null;if(hit)jumpHd(hit.id);}}}).catch(function(e){if(openNote===path){noteDoc={frontmatter:{},tags:[],links_in:[],links_out:[],headings:[],neighbours:[],unresolved:[],html:"<pre>no preview ("+esc(e.status||e)+")</pre>"};go("notes",true);}});}
var nqTimer=null;
function searchNotes(q){noteQ=q;clearTimeout(nqTimer);if(!q.trim()){noteHits=null;go("notes",true);return;}
  var ps=document.getElementById("nqs");if(ps)ps.textContent="…";
  var done=function(h){if(noteQ!==q)return;noteHits=h;var el=document.getElementById("nq"),pos=el&&el.selectionStart;go("notes",true);el=document.getElementById("nq");if(el){el.focus();try{el.setSelectionRange(pos,pos);}catch(x){}}};
  nqTimer=setTimeout(function(){getJSON("/api/notes/search?q="+encodeURIComponent(q)).then(done).catch(function(){done({count:0,hits:[],error:true});});},250);}
function closeNote(){var p=openNote;openNote=null;noteDoc=null;go("notes",true);var f=grid.querySelector('[data-note="'+p.replace(/"/g,'\\"')+'"]');if(f)f.focus();}
export function keys(k){if(N)(N.latest||[]).forEach(function(n){k.notes.push("note:"+n.path+"@"+n.mtime);});
  if(T&&T.daily)k.notes.push("daily:"+T.daily+"@"+T.date);}
export function read(q){noteFilter={};q.split("&").forEach(function(kv){var p=kv.split("=");if(/^(folder|status|tag)$/.test(p[0])&&p[1])noteFilter[p[0]]=decodeURIComponent(p[1]);});}
if(/^#notes\?/.test(location.hash))read(location.hash.slice(7));
export function enter(force){if(!force)loadNotes();}
export function refresh(){if(grid.dataset.live){loadDay();return true;}}
export function input(e){if(e.target.id==="nq")searchNotes(e.target.value);}
export function click(e){
  var hd=e.target.closest("[data-hd]");if(hd){e.preventDefault();if(hd.dataset.note&&hd.dataset.note!==openNote){pendingHd=hd.dataset.hd;openNoteDoc(hd.dataset.note);}else jumpHd(hd.dataset.hd);return true;}
  var nn=e.target.closest("[data-note]");if(nn){e.preventDefault();openNoteDoc(nn.dataset.note);return true;}
  if(e.target.closest("[data-links]")){showLinks=!showLinks;go("notes",true);return true;}
  if(e.target.closest("[data-close-note]")){closeNote();return true;}
  var so=e.target.closest("[data-sort]");if(so){noteSort=so.dataset.sort;go("notes",true);return true;}
  var fc=e.target.closest("[data-facet]");if(fc){var kd=fc.dataset.facet;if(!kd)noteFilter={};else noteFilter[kd]=noteFilter[kd]===fc.dataset.v?"":fc.dataset.v;go("notes",true);return true;}
}
export function key(e){var k=e.key;
  if(k==="Enter"&&e.target.closest("[data-note]")){openNoteDoc(e.target.closest("[data-note]").dataset.note);e.preventDefault();return true;}
  if(k==="j"||k==="k"){var L=noteList(),at=-1;L.forEach(function(x,n){if(x.path===openNote)at=n;});var nx=Math.max(0,Math.min(L.length-1,at+(k==="j"?1:-1)));if(L[nx]&&L[nx].path!==openNote)openNoteDoc(L[nx].path);e.preventDefault();return true;}
  if(k==="b"){showLinks=!showLinks;go("notes",true);e.preventDefault();return true;}
  if(k==="/"){var nq=document.getElementById("nq");if(nq){nq.focus();e.preventDefault();}return true;}
  if(k==="Escape"&&openNote){closeNote();return true;}
}

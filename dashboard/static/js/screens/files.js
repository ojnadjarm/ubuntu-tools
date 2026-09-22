/* Files screen: the ~/drop browser with tree, filter, sort, preview and the fullscreen viewer. */
import {esc,size,when,ago,cell,table,stat} from "../core/fmt.js";
import {getJSON,getText,postJSON} from "../core/api.js";
import {cur,SEEN,go,markSeen} from "../core/router.js";
import * as lb from "../ui/lightbox.js";
import {copyText,copied} from "../ui/copy.js";
import {ask} from "../ui/confirm.js";
var D=null,grid=null,openFile=null,cwd="",LS={},FETCHING={},FS={open:{"":1}},fsort="name",fdesc=false,fq="";
var board=document.getElementById("board");
var PREVIEW={image:1,markdown:1,text:1,code:1,pdf:1,video:1,audio:1};
try{var _fs=JSON.parse(localStorage.getItem("eye.files")||"{}");FS.open=_fs.open||FS.open;cwd=_fs.cwd||"";}catch(e){}
function saveFS(){FS.cwd=cwd;try{localStorage.setItem("eye.files",JSON.stringify(FS));}catch(e){}}
function fjoin(d,n){return d?d+"/"+n:n;}
function fdir(p){var i=p.lastIndexOf("/");return i<0?"":p.slice(0,i);}
function fsName(p){return "~/drop"+(p?"/"+p:"");}
export function hash(){return "#files"+(cwd?"?p="+encodeURIComponent(cwd):"");}
function loadDir(p){if(FETCHING[p])return;FETCHING[p]=1;
  getJSON("/api/ls?p="+encodeURIComponent(p)).catch(function(e){return {error:e.message};})
  .then(function(j){delete FETCHING[p];LS[p]=j;if(cur==="files")go("files",true);});}
function ensureDirs(){if(!LS[cwd])loadDir(cwd);Object.keys(FS.open).forEach(function(p){if(FS.open[p]&&!LS[p])loadDir(p);});}
function cd(p){cwd=p;openFile=null;fq="";var q=p;while(true){FS.open[q]=1;if(!q)break;q=fdir(q);}saveFS();if(!LS[p])loadDir(p);go("files",true);board.scrollTop=0;}
function treeNode(p,name,lvl){var d=LS[p],open=!!FS.open[p],kids="",sub='<div class="tn" style="--l:'+(lvl+1)+'"><s>';
  if(open){if(!d)kids=sub+'reading…</s></div>';
    else if(d.error)kids=sub+'<i class="gold">could not read</i></s></div>';
    else{var subs=d.items.filter(function(x){return x.dir;});kids=subs.map(function(x){return treeNode(fjoin(p,x.name),x.name,lvl+1);}).join("")||sub+'no subfolders</s></div>';}}
  return '<div class="tn'+(p===cwd?" on":"")+'" style="--l:'+lvl+'"><button data-tog="'+esc(p)+'" aria-expanded="'+open+'" aria-label="'+(open?"collapse":"expand")+' '+esc(name)+'">'+(open?"▾":"▸")+'</button><button data-cd="'+esc(p)+'"'+(p===cwd?' aria-current="true"':'')+'>'+esc(name)+'</button></div>'+kids;}
function fmatch(x){return !fq||x.name.toLowerCase().indexOf(fq.toLowerCase())>=0;}
function fsorted(items){var k=fsort,d=fdesc?-1:1;return items.slice().sort(function(a,b){if(a.dir!==b.dir)return a.dir?-1:1;var r=k==="size"?(a.bytes||0)-(b.bytes||0):k==="date"?a.mtime-b.mtime:a.name.localeCompare(b.name,undefined,{numeric:true,sensitivity:"base"});return r*d;});}
export function render(g,d){grid=g;D=d;
  var d=LS[cwd],items=d&&!d.error?d.items:[],list=fsorted(items),shown=list.filter(fmatch),dr=D.drop||{};
  var segs=cwd?cwd.split("/"):[],acc="",crumbs='<div class="crumbs"><button data-cd=""'+(cwd?"":' aria-current="true"')+'>~/drop</button>'+segs.map(function(n,i){acc=fjoin(acc,n);return '<i>/</i><button data-cd="'+esc(acc)+'"'+(i===segs.length-1?' aria-current="true"':'')+'>'+esc(n)+'</button>';}).join("")+'</div>';
  var sb=function(k){return '<button class="btn'+(fsort===k?"":" ghost")+'" data-sort="'+k+'" aria-pressed="'+(fsort===k)+'">'+k+(fsort===k?(fdesc?" ▾":" ▴"):"")+'</button>';};
  var bar='<div class="fbar"><input id="fq" type="search" placeholder="filter this folder" value="'+esc(fq)+'" autocomplete="off" aria-label="filter"><span class="k">sort</span>'+sb("name")+sb("size")+sb("date")+'<s id="fcount">'+(fq?shown.length+" of ":"")+items.length+' items</s></div>';
  var v=openFile&&fdir(openFile)===cwd?items.filter(function(f){return fjoin(cwd,f.name)===openFile;})[0]:null,viewer="";
  if(v){
    var src="/files/"+openFile.split("/").map(encodeURIComponent).join("/"),im,media=v.kind==="image"||v.kind==="video";
    if(v.kind==="image")im='<img src="'+src+'" alt="'+esc(v.name)+'" decoding="async" data-full="'+esc(openFile)+'">';
    else if(v.kind==="video")im='<video src="'+src+'" controls playsinline></video>';
    else if(v.kind==="audio")im='<audio src="'+src+'" controls style="width:100%;margin:12px 0"></audio>';
    else if(v.kind==="pdf")im='<iframe src="'+src+'" title="'+esc(v.name)+'"></iframe>';
    else if(PREVIEW[v.kind])im='<div class="prose" id="txt"><pre>loading…</pre></div>';
    else im='<div class="empty"><b>binary file</b> — no preview; download it ('+size(v.bytes)+', '+esc(v.mime||"unknown type")+')</div>';
    viewer='<div class="viewer"><div class="im" id="vim">'+im+'</div><div class="meta"><b>'+esc(v.name)+'</b>'+esc(v.kind)+' · '+size(v.bytes)+' · '+esc(v.mime)+'<br>'+esc(when(v.mtime))+' · '+esc(fsName(cwd))+'<div class="btns">'+(media?'<button class="btn gold" data-full="'+esc(openFile)+'">fullscreen ⤢</button>':'')+'<a class="btn" href="'+src+'?dl=1">download ↓</a><button class="btn ghost" data-copy="'+esc(fsName(openFile))+'">copy path</button><button class="btn ghost" data-close>close · esc</button></div></div></div>';
  }
  var imgs=shown.filter(function(f){return f.kind==="image";}).map(function(x){var p=fjoin(cwd,x.name);return '<div class="thumb'+(p===openFile?' open':'')+'" data-file="'+esc(p)+'" tabindex="0" role="button"><div class="im"><img src="/'+(/\.svg$/i.test(x.name)?"files":"thumb")+'/'+p.split("/").map(encodeURIComponent).join("/")+'" alt="" loading="lazy" decoding="async"></div><div class="nm">'+esc(x.name)+'</div><div class="sz">'+size(x.bytes)+'</div></div>';}).join("");
  var rows=list.map(function(x){var p=fjoin(cwd,x.name),k="file:"+x.name+"@"+x.mtime,href="/files/"+p.split("/").map(encodeURIComponent).join("/"),cp='<button data-copy="'+esc(fsName(p))+'">copy path</button><button class="del" data-del="'+esc(p)+'"'+(x.dir?' data-dir="1"':'')+' aria-label="delete '+esc(x.name)+'">delete</button>';
    if(x.dir)return '<tr'+(fmatch(x)?"":" hidden")+'><td class="n"><button data-cd="'+esc(p)+'">'+esc(x.name)+'/</button></td><td class="kd"><span class="k">folder</span></td><td class="p">—</td><td class="a" title="'+esc(when(x.mtime))+'">'+esc(ago(new Date(x.mtime*1000)))+'</td><td class="go"><button data-cd="'+esc(p)+'">open</button>'+cp+'</td></tr>';
    return '<tr'+(p===openFile?' class="sel"':'')+(fmatch(x)?"":" hidden")+'><td class="n'+(SEEN[k]?'':' fresh')+'" data-new="'+esc(k)+'">'+esc(x.name)+'</td><td class="kd"><span class="k">'+esc(x.kind)+'</span></td><td class="p">'+size(x.bytes)+'</td><td class="a" title="'+esc(when(x.mtime))+'">'+esc(ago(new Date(x.mtime*1000)))+'</td><td class="go"><button data-file="'+esc(p)+'">'+(PREVIEW[x.kind]?"preview":"info")+'</button><a href="'+href+'?dl=1">download ↓</a>'+cp+'</td></tr>';}).join("");
  var empty=!d?"reading…":d.error?"<b>could not read.</b> "+esc(d.error):!items.length?"<b>empty folder.</b> nothing in "+esc(fsName(cwd)):"";
  var tbl=empty?'<div class="empty">'+empty+'</div>':table([["name"],["kind","kd"],["size","p"],["modified","a"],['<span class="sr-only">open</span>',"go"]],rows)+(shown.length?"":'<div class="empty" id="fnone"><b>no match</b> for “'+esc(fq)+'”</div>');
  var nopen=Object.keys(FS.open).filter(function(k){return FS.open[k];}).length;
  return cell("two3 read","browser","<s>"+esc(fsName(cwd))+"</s>",crumbs+bar+viewer+(imgs?'<div class="thumbs">'+imgs+'</div>':'')+tbl,0)
    +cell("third side","folders","<s>"+nopen+" open</s>",'<div class="tree">'+treeNode("","~/drop",0)+'</div>',1)
    +cell("third side","this folder","<s>"+esc(cwd?cwd.split("/").pop():"drop")+"</s>",stat("items",d&&!d.error?d.count:"—")+stat("size",d&&!d.error?size(d.bytes):"—")+stat("served on",'<a href="'+esc(dr.url||"#")+'" target="_blank" rel="noopener">:8070</a>',"g")+stat("auth","none","gold")+'<div class="btns"><a class="btn" href="'+esc(dr.url||"#")+'" target="_blank" rel="noopener">open drop ↗</a><button class="btn gold" data-copy="'+esc(dr.url||"")+'">copy folder link</button><button class="btn ghost" data-copy="'+esc(fsName(cwd))+'">copy path</button></div>',2);
}
function applyFilter(){var n=0;grid.querySelectorAll(".tw tbody tr").forEach(function(tr){var nm=tr.querySelector("td.n").textContent.replace(/\/$/,"");var ok=!fq||nm.toLowerCase().indexOf(fq.toLowerCase())>=0;tr.hidden=!ok;if(ok)n++;});
  grid.querySelectorAll(".thumb").forEach(function(t){t.hidden=!!fq&&t.querySelector(".nm").textContent.toLowerCase().indexOf(fq.toLowerCase())<0;});
  var c=document.getElementById("fcount"),d=LS[cwd];if(c&&d&&d.items)c.textContent=(fq?n+" of ":"")+d.items.length+" items";var no=document.getElementById("fnone");if(no)no.hidden=n>0;}
function loadText(name){var el=document.getElementById("txt");if(!el)return;
  getText("/files/"+name.split("/").map(encodeURIComponent).join("/")+"?md=1")
  .then(function(h){if(openFile===name&&document.getElementById("txt"))document.getElementById("txt").innerHTML=h;})
  .catch(function(e){if(document.getElementById("txt"))document.getElementById("txt").innerHTML='<pre>no preview ('+esc(e.status||e)+')</pre>';});}
function del(b){var p=b.dataset.del,dir=!!b.dataset.dir;
  ask({title:dir?"Move folder to trash?":"Move to trash?",item:p.split("/").pop()+(dir?"/":""),body:fsName(p)+(dir?" and everything in it leave the drop; original files stay.":" leaves the drop; the original file stays."),action:"Move to trash"}).then(function(ok){if(!ok)return;
  postJSON("/api/files/delete",{path:p}).then(function(){
    if(openFile&&(openFile===p||openFile.indexOf(p+"/")===0))openFile=null;
    [LS,FS.open].forEach(function(o){Object.keys(o).forEach(function(k){if(k===p||k.indexOf(p+"/")===0)delete o[k];});});
    saveFS();loadDir(fdir(p));
  }).catch(function(e){alert("Could not move it to the trash: "+e.message);});});}
function scrollRead(){requestAnimationFrame(function(){var c=grid.querySelector(".cell.read");if(c)c.scrollIntoView({block:"start"});});}
function lbList(){var dir=fdir(openFile||""),d=LS[dir];return ((d&&d.items)||[]).filter(function(f){return f.kind==="image"||f.kind==="video";}).map(function(f){return {name:f.name,kind:f.kind,path:fjoin(dir,f.name)};});}
function closeFile(){var p=openFile;openFile=null;go("files",true);var f=grid.querySelector('[data-file="'+p.replace(/"/g,'\\"')+'"]');if(f)f.focus();}
export function read(q){var pm=/(?:^|&)p=([^&]*)/.exec(q);cwd=pm?decodeURIComponent(pm[1]):"";}
if(/^#files\?/.test(location.hash))read(location.hash.slice(7));
export function enter(){ensureDirs();if(openFile)loadText(openFile);}
export function refresh(){if(openFile)return true;loadDir(cwd);}
export function input(e){if(e.target.id==="fq"){fq=e.target.value;applyFilter();}}
export function click(e){
  if(lb.click(e))return true;
  var fl=e.target.closest("[data-full]");if(fl){lb.open(lbList,fl.dataset.full,fl);return true;}
  var db=e.target.closest("[data-del]");if(db){del(db);return true;}
  var cdb=e.target.closest("[data-cd]");if(cdb){cd(cdb.dataset.cd);return true;}
  var tg=e.target.closest("[data-tog]");if(tg){var tp=tg.dataset.tog;FS.open[tp]=!FS.open[tp];saveFS();if(FS.open[tp]&&!LS[tp])loadDir(tp);go("files",true);return true;}
  var fso=e.target.closest("[data-sort]");if(fso){var sk=fso.dataset.sort;if(sk===fsort)fdesc=!fdesc;else{fsort=sk;fdesc=sk!=="name";}go("files",true);return true;}
  var t=e.target.closest("[data-file]");if(t){openFile=t.dataset.file;go("files",true);scrollRead();var bn=openFile.split("/").pop();markSeen(((D.drop||{}).files||[]).filter(function(f){return f.name===bn;}).map(function(f){return "file:"+f.name+"@"+f.mtime;}));return true;}
  if(e.target.closest("[data-close]")){closeFile();return true;}
  var c=e.target.closest("[data-copy]");if(c){copied(c,copyText(c.dataset.copy));return true;}
}
export function key(e){var k=e.key;
  if(lb.isOpen()){lb.key(e);return true;}
  if((k==="Enter"||(k===" "&&e.target.getAttribute("role")==="button"))&&e.target.closest("[data-file]")){openFile=e.target.closest("[data-file]").dataset.file;go("files",true);scrollRead();e.preventDefault();return true;}
  if(k==="/"){var fqe=document.getElementById("fq");if(fqe){fqe.focus();e.preventDefault();}return true;}
  if(k==="Escape"&&openFile){closeFile();return true;}
}

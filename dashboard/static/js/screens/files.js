/* Files screen: the ~/drop browser with tree, filter, sort, preview and the fullscreen viewer. */
import {esc,size,when,ago,cell,table,stat} from "../core/fmt.js";
import {getJSON,getText,postJSON} from "../core/api.js";
import {cur,SEEN,go,markSeen} from "../core/router.js";
import * as lb from "../ui/lightbox.js";
import {copyText,copied} from "../ui/copy.js";
import {ask} from "../ui/confirm.js";
import {toast} from "../ui/toast.js";
var D=null,grid=null,openFile=null,cwd="",LS={},FETCHING={},FS={open:{"":1}},fsort="name",fdesc=false,fq="";
var PICK={},anchor=null,picking=false,lp=0,lpXY=[0,0],lpFired=false;
var board=document.getElementById("board");
if(!document.querySelector('link[href="/static/css/files.css"]')){var _l=document.createElement("link");_l.rel="stylesheet";_l.href="/static/css/files.css";document.head.appendChild(_l);}
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
function cd(p){cwd=p;openFile=null;fq="";PICK={};anchor=null;picking=false;var q=p;while(true){FS.open[q]=1;if(!q)break;q=fdir(q);}saveFS();if(!LS[p])loadDir(p);go("files",true);board.scrollTop=0;}
function treeNode(p,name,lvl){var d=LS[p],open=!!FS.open[p],kids="",sub='<div class="tn" style="--l:'+(lvl+1)+'"><s>';
  if(open){if(!d)kids=sub+'reading…</s></div>';
    else if(d.error)kids=sub+'<i class="gold">could not read</i></s></div>';
    else{var subs=d.items.filter(function(x){return x.dir;});kids=subs.map(function(x){return treeNode(fjoin(p,x.name),x.name,lvl+1);}).join("")||sub+'no subfolders</s></div>';}}
  return '<div class="tn'+(p===cwd?" on":"")+'" style="--l:'+lvl+'"><button data-tog="'+esc(p)+'" aria-expanded="'+open+'" aria-label="'+(open?"collapse":"expand")+' '+esc(name)+'">'+(open?"▾":"▸")+'</button><button data-cd="'+esc(p)+'"'+(p===cwd?' aria-current="true"':'')+'>'+esc(name)+'</button></div>'+kids;}
function fmatch(x){return !fq||x.name.toLowerCase().indexOf(fq.toLowerCase())>=0;}
function fsorted(items){var k=fsort,d=fdesc?-1:1;return items.slice().sort(function(a,b){if(a.dir!==b.dir)return a.dir?-1:1;var r=k==="size"?(a.bytes||0)-(b.bytes||0):k==="date"?a.mtime-b.mtime:a.name.localeCompare(b.name,undefined,{numeric:true,sensitivity:"base"});return r*d;});}
export function render(g,d){grid=g;D=d;
  var d=LS[cwd],items=d&&!d.error?d.items:[],list=fsorted(items),shown=list.filter(fmatch),dr=D.drop||{};
  if(d&&!d.error){var have={};items.forEach(function(x){have[fjoin(cwd,x.name)]=1;});Object.keys(PICK).forEach(function(k){if(!have[k])delete PICK[k];});}
  var np=Object.keys(PICK).length,nall=shown.filter(function(x){return PICK[fjoin(cwd,x.name)];}).length;
  if(!np)picking=false;
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
  var rows=list.map(function(x){var p=fjoin(cwd,x.name),k="file:"+x.name+"@"+x.mtime,pk='<td class="pk"><label><input type="checkbox" data-pick="'+esc(p)+'"'+(PICK[p]?" checked":"")+' aria-label="select '+esc(x.name)+'"></label></td>',href="/files/"+p.split("/").map(encodeURIComponent).join("/"),cp='<button data-copy="'+esc(fsName(p))+'">copy path</button><button class="del" data-del="'+esc(p)+'"'+(x.dir?' data-dir="1"':'')+' aria-label="delete '+esc(x.name)+'">delete</button>';
    if(x.dir)return '<tr'+(PICK[p]?' class="pkd"':'')+(fmatch(x)?"":" hidden")+'>'+pk+'<td class="n"><button data-cd="'+esc(p)+'">'+esc(x.name)+'/</button></td><td class="kd"><span class="k">folder</span></td><td class="p">—</td><td class="a" title="'+esc(when(x.mtime))+'">'+esc(ago(new Date(x.mtime*1000)))+'</td><td class="go"><button data-cd="'+esc(p)+'">open</button><a href="'+zipHref([p])+'" download>download ↓</a>'+cp+'</td></tr>';
    var tc=[p===openFile?"sel":"",PICK[p]?"pkd":""].join(" ").trim();
    return '<tr'+(tc?' class="'+tc+'"':'')+(fmatch(x)?"":" hidden")+'>'+pk+'<td class="n'+(SEEN[k]?'':' fresh')+'" data-new="'+esc(k)+'">'+esc(x.name)+'</td><td class="kd"><span class="k">'+esc(x.kind)+'</span></td><td class="p">'+size(x.bytes)+'</td><td class="a" title="'+esc(when(x.mtime))+'">'+esc(ago(new Date(x.mtime*1000)))+'</td><td class="go"><button data-file="'+esc(p)+'">'+(PREVIEW[x.kind]?"preview":"info")+'</button><a href="'+href+'?dl=1">download ↓</a>'+cp+'</td></tr>';}).join("");
  var empty=!d?"reading…":d.error?"<b>could not read.</b> "+esc(d.error):!items.length?"<b>empty folder.</b> nothing in "+esc(fsName(cwd)):"";
  var pbar=np?'<div class="fpick" role="region" aria-label="selection"><b aria-live="polite">'+np+' selected</b><s>'+pickSize()+'</s><span class="acts">'+(nall<shown.length?'<button class="btn ghost" data-pall>all '+shown.length+'</button>':'')+'<button class="btn ghost" data-pclear>clear</button><a class="btn" href="'+zipHref(Object.keys(PICK))+'" download>download '+np+'</a><button class="btn danger" data-pdel>delete '+np+'</button></span></div>':'';
  if(np)requestAnimationFrame(function(){var a=document.getElementById("fall");if(a)a.indeterminate=nall>0&&nall<shown.length;});
  var tbl=empty?'<div class="empty">'+empty+'</div>':'<div class="fsel'+(picking?" picking":"")+'">'+table([['<label><input type="checkbox" id="fall"'+(shown.length&&nall===shown.length?" checked":"")+' aria-label="select all in this folder"></label>',"pk"],["name"],["kind","kd"],["size","p"],["modified","a"],['<span class="sr-only">open</span>',"go"]],rows)+'</div>'+pbar+(shown.length?"":'<div class="empty" id="fnone"><b>no match</b> for “'+esc(fq)+'”</div>');
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
  ask({title:dir?"Move folder to trash?":"Move to trash?",item:p.split("/").pop()+(dir?"/":""),body:fsName(p)+(dir?" and everything in it leave the drop; original files stay.":" leaves the drop; the original file stays."),action:"Move to trash"}).then(function(ok){if(ok)trashNow([p]);});}
function zipHref(ps){return "/api/files/zip?"+ps.map(function(p){return "p="+encodeURIComponent(p);}).join("&");}
function plural(n,w){return n+" "+w+(n===1?"":"s");}
function itemOf(p){var d=LS[fdir(p)],n=p.split("/").pop();return ((d&&d.items)||[]).filter(function(x){return x.name===n;})[0]||{};}
function pickSize(){var b=0,f=0;Object.keys(PICK).forEach(function(p){var x=itemOf(p);if(x.dir)f++;else b+=x.bytes||0;});
  return f?(b?size(b)+" + ":"")+plural(f,"folder"):size(b);}
function visible(){var d=LS[cwd];return fsorted((d&&d.items)||[]).filter(fmatch).map(function(x){return fjoin(cwd,x.name);});}
function setPick(p,on){if(on)PICK[p]=1;else delete PICK[p];}
function pickOne(p,on,range){var v=visible(),a=v.indexOf(anchor),z=v.indexOf(p);
  if(range&&a>=0&&z>=0)v.slice(Math.min(a,z),Math.max(a,z)+1).forEach(function(q){setPick(q,on);});else setPick(p,on);
  anchor=p;go("files",true);}
function pickAll(on){if(on)visible().forEach(function(q){setPick(q,true);});else{PICK={};picking=false;}go("files",true);}
function delMany(){var ps=Object.keys(PICK);
  postJSON("/api/files/delete-many",{paths:ps,dry:true}).then(function(c){
    var names=ps.map(function(p){return p.split("/").pop()+(itemOf(p).dir?"/":"");});
    return ask({title:"Move "+plural(c.count,"item")+" to trash?",item:plural(c.count,"item")+" · "+size(c.bytes),body:names.slice(0,5).join(", ")+(names.length>5?" and "+(names.length-5)+" more":"")+" leave the drop; original files stay. Undo for 10 s.",action:"Move "+c.count+" to trash"})
    .then(function(ok){if(ok)trashNow(ps);});
  }).catch(function(e){toast("Nothing deleted: "+e.message,{ms:8000});});}
function forgetPaths(ps){ps.forEach(function(p){
    if(openFile&&(openFile===p||openFile.indexOf(p+"/")===0))openFile=null;delete PICK[p];
    [LS,FS.open].forEach(function(o){Object.keys(o).forEach(function(k){if(k===p||k.indexOf(p+"/")===0)delete o[k];});});});
  saveFS();}
function reload(ps){ps.map(fdir).filter(function(x,i,a){return a.indexOf(x)===i;}).forEach(loadDir);}
function trashNow(ps){postJSON("/api/files/delete-many",{paths:ps}).then(function(r){var t=r.trashed,f=r.failed||[];forgetPaths(t);reload(ps);
    toast(f.length?"Deleted "+t.length+" of "+plural(t.length+f.length,"item")+" · "+f.length+" could not":"Deleted "+plural(t.length,"item"),{action:"Undo",ms:f.length?15000:10000,run:function(){undo(t);}});
  }).catch(function(e){reload(ps);toast("Could not move it to the trash: "+e.message,{ms:8000});});}
function undo(ps){postJSON("/api/files/restore",{paths:ps}).then(function(r){
    toast("Restored "+plural(r.restored.length,"item")+(r.failed.length?" · "+r.failed.length+" could not":""));
  }).catch(function(e){toast("Undo failed: "+e.message,{ms:8000});}).then(function(){reload(ps);});}
board.addEventListener("pointerdown",function(e){lpFired=false;clearTimeout(lp);lp=0;
  if(cur!=="files"||e.pointerType==="mouse")return;var tr=e.target.closest(".fsel tbody tr");if(!tr||e.target.closest("td.go, td.pk"))return;
  lpXY=[e.clientX,e.clientY];lp=setTimeout(function(){var c=tr.querySelector("[data-pick]");lp=0;if(!c||!c.isConnected)return;lpFired=picking=true;pickOne(c.dataset.pick,true,false);},500);});
board.addEventListener("pointermove",function(e){if(lp&&Math.hypot(e.clientX-lpXY[0],e.clientY-lpXY[1])>10){clearTimeout(lp);lp=0;}});
["pointerup","pointercancel"].forEach(function(t){board.addEventListener(t,function(){clearTimeout(lp);lp=0;});});
board.addEventListener("contextmenu",function(e){if(lpFired&&cur==="files")e.preventDefault();});
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
  if(lpFired){lpFired=false;e.preventDefault();return true;}
  var pk=e.target.closest("[data-pick]");if(pk){pickOne(pk.dataset.pick,pk.checked,e.shiftKey);return true;}
  if(e.target.id==="fall"){pickAll(e.target.checked);return true;}
  if(e.target.closest("[data-pall]")){pickAll(true);return true;}
  if(e.target.closest("[data-pclear]")){pickAll(false);return true;}
  if(e.target.closest("[data-pdel]")){delMany();return true;}
  var ptr=picking&&e.target.closest(".fsel tbody tr");if(ptr){if(!e.target.closest("td.go, td.pk")){var pc=ptr.querySelector("[data-pick]");pickOne(pc.dataset.pick,!PICK[pc.dataset.pick],false);e.preventDefault();}return true;}
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
  if(k==="Escape"&&Object.keys(PICK).length){pickAll(false);return true;}
}

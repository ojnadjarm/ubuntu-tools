/* To do screen: the owner-only steps from the owner-todo ledger, each with its exact steps, Copy and Done. */
import {esc,when,cell} from "../core/fmt.js";
import {postJSON} from "../core/api.js";
import {go} from "../core/router.js";
import {copyText,copied} from "../ui/copy.js";
import {ask} from "../ui/confirm.js";
var D=null;
export function render(grid,d){D=d;
  var it=D.todo||[];
  var rows=it.map(function(x){
    return '<li class="todo"><h3><b>'+esc(x.id)+'</b>'+esc(x.text)+'</h3>'
      +(x.how?'<pre>'+esc(x.how)+'</pre>':"")
      +'<div class="tf"><s>'+(x.src?esc(x.src)+" · ":"")+"added "+esc(when(x.added))+'</s>'
      +(x.how?'<button class="btn ghost" data-copy="'+esc(x.id)+'">copy</button>':"")
      +'<button class="btn gold" data-done="'+esc(x.id)+'">done</button></div></li>';
  }).join("");
  return cell("wide","waiting on you","<s>"+it.length+" open · oldest first</s>",
    it.length?'<ol class="todos">'+rows+'</ol>':'<div class="empty"><b>nothing.</b> no step waits on you</div>',0);
}
export function click(e){
  var c=e.target.closest("[data-copy]");if(c){var x=find(c.dataset.copy);if(x)copied(c,copyText(x.how));return true;}
  var d=e.target.closest("[data-done]");if(d){done(d.dataset.done);return true;}
}
function find(id){return (D.todo||[]).filter(function(x){return x.id===id;})[0];}
function done(id){var x=find(id);if(!x)return;
  ask({title:"Mark it done?",item:x.text,body:"It leaves this list and the headline count. Undo: owner-todo reopen "+id,action:"Done"}).then(function(ok){if(!ok)return;
  postJSON("/api/owner-todo/done",{id:id}).then(function(){D.todo=D.todo.filter(function(t){return t.id!==id;});
    if(D.verdict)D.verdict.needs=(D.verdict.needs||[]).filter(function(n){return n.todo!==id;});go("todo",true);})
  .catch(function(e){alert("Could not mark it done: "+e.message);});});}

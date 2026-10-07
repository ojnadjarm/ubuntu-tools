/* Tickets page: Close marks a ticket done, Delete (done tickets) removes its section after a confirm; then the page reloads from the file. */
import {postJSON} from "./core/api.js";
import {ask} from "./ui/confirm.js";
var key=document.querySelector("main.page").dataset.project;
document.addEventListener("click",function(e){
  var b=e.target.closest("button[data-tk]");if(!b)return;
  var act=b.dataset.tk,id=b.dataset.id,h=b.parentNode.previousElementSibling;
  var go=act==="delete"?ask({title:"Delete "+id+"?",item:h?h.textContent:id,body:"Its whole section leaves TICKETS.md; a backup copy is kept.",action:"Delete"}):Promise.resolve(true);
  go.then(function(ok){if(!ok)return;b.disabled=true;
    return postJSON("/api/projects/tickets/"+act,{project:key,id:id}).then(function(){location.reload();});
  }).catch(function(err){b.disabled=false;alert(err.message);});
});

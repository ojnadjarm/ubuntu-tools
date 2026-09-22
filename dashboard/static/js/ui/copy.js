/* Clipboard copy with a textarea fallback outside secure contexts, and the "copied" flash on the button. */
export function copyText(t){if(navigator.clipboard&&window.isSecureContext)return navigator.clipboard.writeText(t);
  var ta=document.createElement("textarea");ta.value=t;ta.style.cssText="position:fixed;opacity:0";document.body.appendChild(ta);ta.select();var ok=false;try{ok=document.execCommand("copy");}catch(x){}ta.remove();return ok?Promise.resolve():Promise.reject();}
export function copied(btn,pr){var t=btn.textContent;pr.then(function(){btn.textContent="copied";},function(){btn.textContent="copy failed";}).then(function(){setTimeout(function(){btn.textContent=t;},1500);});}

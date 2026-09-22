/* Fetch helpers: revalidate with the server each time (If-None-Match once it sends ETags), reject with the server's error. */
function fail(r){return r.json().catch(function(){return {};}).then(function(j){var e=new Error(j.error||"http "+r.status);e.status=r.status;throw e;});}
export function getJSON(u){return fetch(u,{cache:"no-cache"}).then(function(r){return r.ok?r.json():fail(r);});}
export function getText(u){return fetch(u,{cache:"no-cache"}).then(function(r){return r.ok?r.text():fail(r);});}
export function postJSON(u,body){return fetch(u,{method:"POST",body:JSON.stringify(body)}).then(function(r){return r.ok?r.json():fail(r);});}

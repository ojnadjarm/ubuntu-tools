/* The 30 s data tick and the 1 s clock, both stopped while the page is hidden. */
export function poll(tick,clock){var timer=null,clk=null;
  function on(v){clearInterval(timer);clearInterval(clk);timer=clk=null;if(v){timer=setInterval(tick,30000);clk=setInterval(clock,1000);}}
  document.addEventListener("visibilitychange",function(){if(document.hidden)on(false);else{tick();on(true);}});
  clock();tick();on(true);}

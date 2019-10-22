let wsLocal = new WebSocket("ws://localhost:25887/");

wsLocal.onerror = (ev) => {
  console.log(ev);
};
wsLocal.onclose = (ev) => {
  console.log(ev);
};
wsLocal.onopen = (ev) => {
  console.log(ev);
};
wsLocal.onmessage = (ev) => {
  //console.log(ev);
  // echo back:
  wsLocal.send(ev.data);
};

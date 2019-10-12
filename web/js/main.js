let ws = new WebSocket("ws://localhost:4590/alttp");
ws.onerror = (ev) => {
  console.log(ev);
};
ws.onclose = (ev) => {
  console.log(ev);
};
ws.onopen = (ev) => {
  console.log(ev);
};
ws.onmessage = (ev) => {
  // echo back message:
  ws.send(ev.data);
};

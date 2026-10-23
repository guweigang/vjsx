// CLI probe. The Python runner supplies only local fixture URLs.
const [url, mode = 'echo'] = process.argv.slice(1);
let errors = 0, messages = 0;
const socket = new WebSocket(url, mode === 'protocol' ? ['fixture.v1'] : []);
socket.binaryType = 'arraybuffer';
const deadline = setTimeout(() => { console.log('FAIL timeout'); socket.close(); }, 5000);
const fail = message => { console.log('FAIL', message); socket.close(); };
socket.onerror = () => errors++;
socket.onopen = () => {
  if (mode === 'reject') return fail('unexpected TLS/upgrade success');
  if (mode === 'disconnect' || mode === 'invalid' || mode === 'flood') return;
  if (mode === 'cancel') return socket.close(3002, 'cancelled');
  if (mode === 'protocol' && socket.protocol !== 'fixture.v1') return fail('subprotocol');
  socket.send('你好');
  socket.send(new Uint8Array([88, 0, 255, 1, 88]).subarray(1, 4));
  socket.send(new Uint8Array([3, 4]).buffer);
  socket.send(new DataView(new Uint8Array([5, 6]).buffer));
};
socket.onmessage = ({data}) => {
  const expected = ['你好', '0,255,1', '3,4', '5,6'];
  const actual = typeof data === 'string' ? data : [...new Uint8Array(data)].join(',');
  if (actual !== expected[messages]) return fail('payload: '+actual);
  if (++messages === 4) socket.close(3001, '完成');
};
socket.onclose = event => {
  clearTimeout(deadline);
  const rejecting = ['reject', 'disconnect', 'invalid', 'flood'].includes(mode);
  if (mode === 'connecting-cancel' && event.code === 1006) console.log('PASS connecting-cancel');
  else if (rejecting && event.code === 1006 && errors > 0) console.log('PASS', mode);
  else if (mode === 'cancel' && event.code === 3002 && event.wasClean) console.log('PASS cancel');
  else if (!rejecting && messages === 4 && event.code === 3001 && event.reason === '完成' && event.wasClean)
    console.log('PASS', mode);
  else console.log('FAIL close', event.code, event.reason, event.wasClean, errors, messages);
};
if (mode === 'connecting-cancel') {
 socket.close(); socket.close();
}

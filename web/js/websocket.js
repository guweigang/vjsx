import * as os from 'qjs:os';
const native = globalThis.__vjsxWebSocketNative;
delete globalThis.__vjsxWebSocketNative;
const sockets = new Map();
const encoder = new TextEncoder();
const decoder = new TextDecoder();
function exception(name, message) { const e = new Error(message); e.name = name; return e; }
class WebSocket extends EventTarget {
  #state = 0; #url; #protocol = ''; #binaryType = 'blob'; #handle; #buffered = 0;
  onopen = null; onmessage = null; onerror = null; onclose = null;
  constructor(url, protocols = []) {
    super();
    let parsed;
    try { parsed = new URL(String(url)); }
    catch { throw exception('SyntaxError', 'Invalid WebSocket URL'); }
    if (parsed.protocol === 'http:') parsed.protocol = 'ws:';
    if (parsed.protocol === 'https:') parsed.protocol = 'wss:';
    if (!['ws:', 'wss:'].includes(parsed.protocol) || parsed.href.includes('#') || parsed.username || parsed.password)
      throw exception('SyntaxError', 'Invalid WebSocket URL');
    protocols = typeof protocols === 'string' ? [protocols] : Array.from(protocols, String);
    if (new Set(protocols).size !== protocols.length || protocols.some(p => !/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(p)))
      throw exception('SyntaxError', 'Invalid or duplicate WebSocket subprotocol');
    this.#url = parsed.href;
    this.#handle = native.start(this.#url, protocols.join(', '), (kind, buffer, text, code, clean) => {
      if (this.#state === 3) return;
      try {
      if (kind === 'sent') { this.#buffered = Math.max(0, this.#buffered - code); return; }
      if (kind === 'open') {
        if (this.#state !== 0) return;
        this.#state = 1; this.#protocol = text;
        this.#emit('open');
      } else if (kind === 'text' || kind === 'binary') {
        if (this.#state !== 1) return;
        const data = kind === 'text' ? decoder.decode(buffer) : this.#binaryType === 'arraybuffer' ? buffer : new Blob([buffer]);
        this.#emit('message', { data, origin: new URL(this.#url).origin, lastEventId: '' });
      } else if (kind === 'error') this.#emit('error', { message: text });
      else if (kind === 'close') {
        this.#state = 3;
        os.setReadHandler(this.#handle.fd, null);
        sockets.delete(this.#handle.id);
        this.#emit('close', { code, reason: text, wasClean: clean });
      }
      } catch (error) {
        this.#state = 3;
        os.setReadHandler(this.#handle.fd, null);
        sockets.delete(this.#handle.id);
        native.send(this.#handle.id, 'cancel', new ArrayBuffer(0), 0);
        throw error;
      }
    });
    sockets.set(this.#handle.id, this.#handle.fd);
    os.setReadHandler(this.#handle.fd, () => native.drain(this.#handle.id));
  }
  #emit(type, fields = {}) {
    const event = Object.assign(new Event(type), fields);
    this.dispatchEvent(event);
    if (typeof this['on' + type] === 'function') this['on' + type].call(this, event);
  }
  get url() { return this.#url; }
  get protocol() { return this.#protocol; }
  get extensions() { return ''; }
  get readyState() { return this.#state; }
  get bufferedAmount() { return this.#buffered; }
  get binaryType() { return this.#binaryType; }
  set binaryType(value) { if (value === 'blob' || value === 'arraybuffer') this.#binaryType = value; }
  send(data) {
    if (this.#state === 0) throw exception('InvalidStateError', 'WebSocket is connecting');
    let kind = 'binary', bytes;
    if (data instanceof ArrayBuffer) bytes = data;
    else if (ArrayBuffer.isView(data)) bytes = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    else if (data instanceof Blob) throw new TypeError('WebSocket.send(Blob) is not supported; use ArrayBuffer');
    else { kind = 'text'; bytes = encoder.encode(String(data)).buffer; }
    if (this.#state >= 2) { this.#buffered += bytes.byteLength; return; }
    if (!native.send(this.#handle.id, kind, bytes, 0)) {
      this.#state = 2;
      native.send(this.#handle.id, 'cancel', new ArrayBuffer(0), 0);
      throw exception('QuotaExceededError', 'WebSocket send queue limit exceeded');
    }
    this.#buffered += bytes.byteLength;
  }
  close(code = 1000, reason = '') {
    code = Number(code); reason = String(reason);
    if (!Number.isInteger(code) || (code !== 1000 && (code < 3000 || code > 4999)))
      throw exception('InvalidAccessError', 'Invalid WebSocket close code');
    const bytes = encoder.encode(reason);
    if (bytes.byteLength > 123) throw exception('SyntaxError', 'WebSocket close reason exceeds 123 bytes');
    if (this.#state >= 2) return;
    const connecting = this.#state === 0;
    this.#state = 2;
    if (!native.send(this.#handle.id, connecting ? 'cancel' : 'close', bytes.buffer, code))
      native.send(this.#handle.id, 'cancel', new ArrayBuffer(0), 0);
  }
}
for (const [name, value] of Object.entries({ CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })) {
  Object.defineProperty(WebSocket, name, { value, enumerable: true });
  Object.defineProperty(WebSocket.prototype, name, { value, enumerable: true });
}
globalThis.WebSocket = WebSocket;
globalThis.__vjsxWebSocketCleanup = () => {
  for (const fd of sockets.values()) os.setReadHandler(fd, null);
  sockets.clear();
};

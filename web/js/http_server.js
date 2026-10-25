import * as os from 'qjs:os';
const native = globalThis.__vjsxHttpServerNative;
delete globalThis.__vjsxHttpServerNative;
const handles = new Map();
const encode = value => value instanceof ArrayBuffer ? new Uint8Array(value) : ArrayBuffer.isView(value) ? new Uint8Array(value.buffer, value.byteOffset, value.byteLength) : new TextEncoder().encode(String(value ?? ''));
const buffer = value => typeof Buffer !== 'undefined' ? Buffer.from(value) : new Uint8Array(value);
class Emitter {
  _events = new Map();
  on(name, fn) { if (typeof fn !== 'function') throw new TypeError('listener must be a function'); const list = this._events.get(name) || []; list.push(fn); this._events.set(name,list); return this; }
  once(name, fn) { const wrap = (...args) => { this.off(name,wrap); fn.apply(this,args); }; wrap.listener = fn; return this.on(name,wrap); }
  off(name, fn) { this._events.set(name,(this._events.get(name)||[]).filter(f=>f!==fn && f.listener!==fn)); return this; }
  removeListener(name, fn) { return this.off(name,fn); }
  removeAllListeners(name) { name === undefined ? this._events.clear() : this._events.delete(name); return this; }
  listenerCount(name) { return this._events.get(name)?.length || 0; }
  emit(name, ...args) { const list = [...(this._events.get(name)||[])]; for (const fn of list) fn.apply(this,args); return !!list.length; }
}
function watch(handle) { handles.set(handle.id,handle.fd); os.setReadHandler(handle.fd,()=>{try{native.drain(handle.id);}catch(error){unwatch(handle);native.stop(handle.id);throw error;}}); }
function unwatch(handle) { if (!handle) return; os.setReadHandler(handle.fd,null); handles.delete(handle.id); }
function command(handle,kind,data='',code=0) {
  const bytes=encode(data);
  if (!handle || !native.send(handle.id,kind,bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),code)) throw new Error('HTTP socket is closed or queue limit reached');
}
class Socket extends Emitter {
  destroyed = false; writable = true; readable = true;
  _handle; _websocket;
  constructor(server, head) { super(); this.server=server; this.remoteAddress=head.remote_address; }
  write(data, encoding, callback) { if(typeof encoding==='function')callback=encoding; command(this._handle,'write',data); callback?.(); return true; }
  end(data='') { command(this._handle,'end',data); this.writable=false; return this; }
  destroy() { if(!this.destroyed) { this.destroyed=true; native.stop(this._handle.id); } return this; }
  setTimeout(ms, callback) { if(ms!==0) throw new Error('Socket timeouts are not supported; use request deadlines'); if(callback)this.on('timeout',callback); return this; }
  setNoDelay() { return this; }
  setKeepAlive() { return this; }
  // Native extension: RFC 6455 validation and framing reuse the V host codec.
  acceptWebSocket() { if(this._websocket)throw new Error('Socket already upgraded'); this._websocket=new ServerWebSocket(this); command(this._handle,'websocket'); return this._websocket; }
}
class ServerWebSocket extends Emitter {
  readyState = 0;
  constructor(socket) { super(); this.socket=socket; }
  send(data) { if(this.readyState>=2)throw new Error('WebSocket is closed'); command(this.socket._handle,typeof data==='string'?'text':'binary',data); }
  close(code=1000,reason='') { if(this.readyState>=2)return; if(!Number.isInteger(code) || !([1000,1001,1002,1003,1007,1008,1009,1011,1012,1013,1014].includes(code)||code>=3000&&code<=4999))throw new RangeError('Invalid WebSocket close code'); if(encode(reason).length>123)throw new RangeError('Close reason too long'); this.readyState=2; try { command(this.socket._handle,'close',reason,code); } catch { this.socket.destroy(); } }
  terminate() { this.socket.destroy(); }
}
class IncomingMessage extends Emitter {
  constructor(head,data,socket) { super(); this.method=head.method; this.url=head.url; this.headers=head.headers; this.httpVersion='1.1'; this.socket=this.connection=socket; this.complete=true; this._body=buffer(data); }
  async *[Symbol.asyncIterator]() { if(this._body.length)yield this._body; }
  setEncoding(encoding) { if(encoding!=='utf8' && encoding!=='utf-8')throw new Error('Only UTF-8 decoding is supported'); this._encoding=encoding; return this; }
  on(name,fn) { super.on(name,fn); if((name==='data'||name==='end')&&!this._scheduled) { this._scheduled=true; Promise.resolve().then(()=>{ if(this._body.length)this.emit('data',this._encoding?new TextDecoder().decode(this._body):this._body); this.emit('end'); }); } return this; }
  destroy() { this.socket.destroy(); return this; }
}
const STATUS_CODES = {101:'Switching Protocols',200:'OK',201:'Created',202:'Accepted',204:'No Content',301:'Moved Permanently',302:'Found',304:'Not Modified',400:'Bad Request',401:'Unauthorized',403:'Forbidden',404:'Not Found',405:'Method Not Allowed',409:'Conflict',413:'Payload Too Large',429:'Too Many Requests',500:'Internal Server Error',501:'Not Implemented',503:'Service Unavailable'};
function headerName(name) { const key=String(name).toLowerCase(); if(!/^[!#$%&'*+.^_`|~0-9a-z-]+$/.test(key))throw new TypeError('Invalid header name'); return key; }
function headerValue(value) { const text=String(value); if(/[\x00-\x08\x0a-\x1f\x7f]/.test(text))throw new TypeError('Invalid header value'); return text; }
class ServerResponse extends Emitter {
  statusCode=200; statusMessage; headersSent=false; writableEnded=false; finished=false; _headers=new Map(); _chunks=[]; _length=0;
  constructor(req) { super(); this.req=req; this.socket=req.socket; }
  setHeader(name,value) { if(this.headersSent)throw new Error('Headers already sent'); this._headers.set(headerName(name),Array.isArray(value)?value.map(headerValue):headerValue(value)); return this; }
  getHeader(name) { return this._headers.get(String(name).toLowerCase()); }
  getHeaders() { return Object.fromEntries(this._headers); }
  hasHeader(name) { return this._headers.has(String(name).toLowerCase()); }
  removeHeader(name) { if(this.headersSent)throw new Error('Headers already sent'); this._headers.delete(String(name).toLowerCase()); }
  writeHead(status,message,headers) { if(this.headersSent)throw new Error('Headers already sent'); this.statusCode=status; if(typeof message==='string')this.statusMessage=headerValue(message); else headers=message; for(const [k,v] of Object.entries(headers||{}))this.setHeader(k,v); return this; }
  write(data,encoding,callback) { if(this.writableEnded)throw new Error('write after end'); const bytes=encode(data); if(this._length+bytes.length>1048576)throw new Error('HTTP response limit exceeded'); this._chunks.push(bytes.slice());this._length+=bytes.length; if(typeof encoding==='function')callback=encoding; callback?.(); return true; }
  end(data,encoding,callback) {
    if(this.writableEnded)return this;
    if(typeof data==='function'){callback=data;data=undefined;} if(typeof encoding==='function')callback=encoding;
    if(data!==undefined)this.write(data);
    if(!Number.isInteger(this.statusCode)||this.statusCode<200||this.statusCode>599)throw new RangeError('Invalid HTTP status code');
    const noBody=this.req.method==='HEAD'||[204,304].includes(this.statusCode);
    if(this.hasHeader('transfer-encoding'))throw new Error('Streaming transfer encoding is not supported');
    if(this.hasHeader('content-length')&&Number(this.getHeader('content-length'))!==this._length)throw new Error('Content-Length mismatch');
    this.setHeader('connection','close');
    this.setHeader('content-length',[204,304].includes(this.statusCode)?0:this._length);
    let text=`HTTP/1.1 ${this.statusCode} ${this.statusMessage||STATUS_CODES[this.statusCode]||'Status'}\r\n`;
    for(const [key,value] of this._headers)for(const val of Array.isArray(value)?value:[value])text+=`${key}: ${val}\r\n`;
    const head=encode(text+'\r\n'); const all=new Uint8Array(head.length+(noBody?0:this._length));all.set(head);
    if(!noBody){let offset=head.length;for(const chunk of this._chunks){all.set(chunk,offset);offset+=chunk.length;}}
    command(this.socket._handle,'end',all);this.headersSent=this.writableEnded=this.finished=true;this._chunks=[];
    callback?.();this.emit('finish');return this;
  }
}
class Server extends Emitter {
  listening=false; maxConnections=64; _sockets=new Set(); _handle; _address=null; _closing=false;
  constructor(options,listener) { super(); if(typeof options==='function')listener=options; else if(options&&Object.keys(options).length)throw new Error('HTTP server options are not supported'); if(listener)this.on('request',listener); }
  listen(port=0,host='0.0.0.0',callback) {
    if(this._handle||this._closing)throw new Error('Server already listening or closing');
    if(typeof port==='object'){callback=typeof host==='function'?host:callback;host=port.host||'0.0.0.0';port=port.port??0;}
    if(typeof host==='function'){callback=host;host='0.0.0.0';}
    if(!Number.isInteger(port)||port<0||port>65535)throw new RangeError('Invalid listen port');
    try {
      this._handle=native.listen(String(host),port,(kind,data,text,code)=>{
        if(kind==='accept') { this._accept(code); }
        else if(kind==='error')this.emit('error',new Error(text));
        else if(kind==='close'){native.forget(this._handle.id);unwatch(this._handle);this._handle=null;this.listening=false;this._maybeClose();}
      });
      this._address={address:host,family:'IPv4',port:this._handle.port};watch(this._handle);this.listening=true;
      if(callback)this.once('listening',callback);Promise.resolve().then(()=>this.emit('listening'));
    } catch(error) { Promise.resolve().then(()=>{if(!this.emit('error',error))throw error;}); }
    return this;
  }
  _accept(id) {
    const socket=new Socket(this,{});
    try { socket._handle=native.connection(this._handle.id,id,(kind,data,text,code,clean)=>{
      if(kind==='request'||kind==='upgrade') {
        const head=JSON.parse(text);socket.remoteAddress=head.remote_address;
        const req=new IncomingMessage(head,data,socket);
        if(kind==='upgrade'){if(!this.emit('upgrade',req,socket,buffer(data)))socket.destroy();}
        else {
          const res=new ServerResponse(req);
          if(!this.listenerCount('request')){res.statusCode=404;res.end();return;}
          for(const fn of [...this._events.get('request')]) {
            try { Promise.resolve(fn.call(this,req,res)).catch(()=>{if(!res.writableEnded){res.statusCode=500;res.end();}}); }
            catch { if(!res.writableEnded){res.statusCode=500;res.end();} }
          }
        }
      } else if(kind==='open'){socket._websocket.readyState=1;socket._websocket.emit('open');}
      else if(kind==='text'||kind==='binary')socket._websocket?.emit('message',buffer(data),kind==='binary');
      else if(kind==='data')socket.emit('data',buffer(data));
      else if(kind==='error'){socket.emit('error',new Error(text));socket._websocket?.emit('error',new Error(text));}
      else if(kind==='close'){
        unwatch(socket._handle);socket.destroyed=true;socket.writable=socket.readable=false;this._sockets.delete(socket);
        if(socket._websocket){socket._websocket.readyState=3;socket._websocket.emit('close',code,text,clean);}
        socket.emit('close');this._maybeClose();
      }
    });
    } catch(error) { this.emit('clientError',error);return; }
    watch(socket._handle);this._sockets.add(socket);
    if(this._closing||this._sockets.size>this.maxConnections)socket.destroy();else this.emit('connection',socket);
  }
  address() { return this.listening?this._address:null; }
  close(callback) { if(callback)this.once('close',callback);this._closing=true;this.listening=false;if(this._handle)native.stop(this._handle.id);else this._maybeClose();return this; }
  closeAllConnections() { for(const socket of this._sockets)socket.destroy(); }
  getConnections(callback) { callback(null,this._sockets.size); }
  _maybeClose() { if(this._closing&&!this._handle&&!this._sockets.size){this._closing=false;this.emit('close');} }
}
function createServer(options,listener) { return new Server(options,listener); }
globalThis.__vjsxHttpServerExports={createServer,Server,IncomingMessage,ServerResponse,STATUS_CODES};
globalThis.__vjsxHttpServerCleanup=()=>{for(const [id,fd] of handles){os.setReadHandler(fd,null);native.stop(id);}handles.clear();};

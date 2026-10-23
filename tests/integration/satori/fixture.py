"""Local HTTP + RFC6455/Feishu protobuf fixture. No real credentials or service."""
import base64, hashlib, http.server, json, socket, socketserver, struct, threading

def varint(n):
    out = bytearray()
    while n > 127: out.append((n & 127) | 128); n >>= 7
    out.append(n)
    return bytes(out)
def field(n, value):
    if isinstance(value, int): return varint(n << 3) + varint(value)
    if isinstance(value, str): value = value.encode()
    return varint((n << 3) | 2) + varint(len(value)) + value

def frame(kind, payload=b'', method=0):
    headers = {'type': kind}
    if method: headers.update(message_id='fixture-event', sum='1', seq='0')
    return (field(1, 1) + field(2, 1) + field(3, 1) + field(4, method)
            + b''.join(field(5, field(1,k)+field(2,v)) for k,v in headers.items()) + field(8,payload))

def wsframe(op, data):
    return bytes([128|op]) + (bytes([len(data)]) if len(data)<126 else b'\x7e'+struct.pack('!H',len(data))) + data

def read(c,n):
    out=b''
    while len(out)<n:
        part=c.recv(n-len(out))
        if not part: raise EOFError()
        out+=part
    return out

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def do_GET(self): self.respond()
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length',0)))
        self.respond()
    def respond(self):
        if self.headers.get('Upgrade','').lower()=='websocket':
            accept=base64.b64encode(hashlib.sha1((self.headers['Sec-WebSocket-Key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            self.send_response(101);self.send_header('Upgrade','websocket');self.send_header('Connection','Upgrade');self.send_header('Sec-WebSocket-Accept',accept);self.end_headers()
            self.wfile.flush()
            self.connection.settimeout(8)
            try:
                # Ping is a wire control frame; fixture expects the browser host's pong.
                self.connection.sendall(wsframe(9,b'fixture-ping'))
                event={'header':{'event_type':'application.bot.menu_v6'},'event':{'event_key':'command:fixture-command','operator':{'operator_id':{'open_id':'fixture-user'}}}}
                sent=False
                while True:
                    op,n=read(self.connection,2);masked=n&128;n&=127
                    if n==126:n=struct.unpack('!H',read(self.connection,2))[0]
                    if n==127:n=struct.unpack('!Q',read(self.connection,8))[0]
                    mask=read(self.connection,4) if masked else b''
                    body=read(self.connection,n)
                    if masked:body=bytes(x^mask[i%4] for i,x in enumerate(body))
                    op&=15
                    if op==10:print('FIXTURE_WIRE_PONG',body.decode(),flush=True)
                    elif op==2:
                        if b'ping' in body and not sent:
                            print('FIXTURE_PROTOBUF_PING',flush=True)
                            self.connection.sendall(wsframe(2,frame('pong')))
                            self.connection.sendall(wsframe(2,frame('event',json.dumps(event).encode(),1)))
                            sent=True
                        elif b'biz_rt' in body and b'200' in body:
                            print('FIXTURE_PROTOBUF_ACK',flush=True)
                            self.connection.sendall(wsframe(8,struct.pack('!H',1000)+b'fixture-complete'))
                    elif op==8:
                        self.connection.sendall(wsframe(8,body));break
            except (EOFError,TimeoutError,ConnectionError): pass
            self.close_connection=True
            return
        print('FIXTURE_HTTP',self.path,flush=True)
        if self.path=='/callback/ws/endpoint':
            data={'code':0,'data':{'URL':'ws://127.0.0.1:18881/gateway?device_id=fixture&service_id=1','ClientConfig':{'PingInterval':60}}}
        elif self.path.endswith('/auth/v3/tenant_access_token/internal'):
            data={'code':0,'tenant_access_token':'fixture-token','expire':3600}
        elif self.path.endswith('/bot/v3/info'):
            data={'code':0,'bot':{'open_id':'fixture-bot','app_name':'Fixture','avatar_url':''}}
        else:data={'code':0,'data':{}}
        body=json.dumps(data).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)

if __name__=='__main__':
    http.server.ThreadingHTTPServer(('127.0.0.1',18881),Handler).serve_forever()

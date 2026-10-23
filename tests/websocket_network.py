#!/usr/bin/env python3
"""Real loopback WS/WSS CLI tests; fixture uses only Python stdlib and openssl."""
import base64, concurrent.futures, hashlib, json, os, pathlib, socket, ssl, struct, subprocess, sys, tempfile, threading
ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = pathlib.Path(sys.argv[1]).resolve()

def read(c,n):
    out=b''
    while len(out)<n:
        part=c.recv(n-len(out))
        if not part: raise EOFError()
        out+=part
    return out

def wire(op,payload,fin=True):
    n=len(payload)
    size=bytes([n]) if n<126 else b'\x7e'+struct.pack('!H',n) if n<=65535 else b'\x7f'+struct.pack('!Q',n)
    return bytes([(128 if fin else 0)|op])+size+payload

class Fixture:
    def __init__(self,tls=None):
        self.tls=tls;self.pongs=0;self.closed=False
        self.socket=socket.socket();self.socket.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        self.socket.bind(('127.0.0.1',0));self.port=self.socket.getsockname()[1];self.socket.listen()
        threading.Thread(target=self.accept,daemon=True).start()
    def accept(self):
        while not self.closed:
            try:c,_=self.socket.accept()
            except OSError:return
            threading.Thread(target=self.handle,args=(c,),daemon=True).start()
    def handle(self,c):
        try:
            c.settimeout(8)
            if self.tls:c=self.tls.wrap_socket(c,server_side=True)
            raw=b''
            while b'\r\n\r\n' not in raw:raw+=c.recv(4096)
            lines=raw.decode().split('\r\n');path=lines[0].split()[1]
            headers=dict(line.split(': ',1) for line in lines[1:] if ': ' in line)
            if path=='/reject':c.sendall(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n');return
            accept=base64.b64encode(hashlib.sha1((headers['Sec-WebSocket-Key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
            protocol=b'Sec-WebSocket-Protocol: fixture.v1\r\n' if 'Sec-WebSocket-Protocol' in headers else b''
            c.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n'+protocol+b'\r\n')
            if path=='/disconnect':return
            if path=='/invalid':c.sendall(b'\x81\x01\xff');return
            if path.endswith('/burst'):
                c.sendall(b''.join(wire(1,b'x') for _ in range(100)));return
            if path=='/flood':c.sendall(b'\x82\x7f'+struct.pack('!Q',1024*1024+1));return
            c.sendall(wire(9,b'ping-proof'))
            while True:
                op,size=read(c,2);masked=size&128;size&=127
                assert masked,'client frame must be masked'
                if size==126:size=struct.unpack('!H',read(c,2))[0]
                if size==127:size=struct.unpack('!Q',read(c,8))[0]
                mask=read(c,4);body=read(c,size);body=bytes(x^mask[i%4] for i,x in enumerate(body));op&=15
                if op==10:
                    assert body==b'ping-proof';self.pongs+=1
                elif op==8:c.sendall(wire(8,body));return
                elif op in (1,2):
                    # Fragment each echo, interleaving a control frame.
                    mid=len(body)//2
                    c.sendall(wire(op,body[:mid],False)+wire(9,b'ping-proof')+wire(0,body[mid:]))
        except (OSError,EOFError,ssl.SSLError):pass
        finally:c.close()
    def close(self):self.closed=True;self.socket.close()

results=[]
def probe(label,url,mode='echo',env=None):
    taskenv={**os.environ,'VJSX_ASSET_ROOT':str(ROOT),**(env or {})}
    run=subprocess.run([str(CLI),'run',str(ROOT/'tests/websocket_network.mjs'),url,mode],env=taskenv,capture_output=True,text=True,timeout=40)
    assert run.returncode==0 and 'PASS '+mode in run.stdout and 'FAIL' not in run.stdout,(label,run.returncode,run.stdout,run.stderr)
    results.append({'case':label,'stdout':run.stdout.strip()})

with tempfile.TemporaryDirectory(prefix='vjsx-wss-') as temp:
    temp=pathlib.Path(temp)
    def openssl(*args):subprocess.run(['openssl',*args],cwd=temp,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout','ca.key','-out','ca.pem','-days','1','-subj','/CN=vjsx test CA')
    openssl('req','-newkey','rsa:2048','-nodes','-keyout','server.key','-out','server.csr','-subj','/CN=localhost')
    (temp/'ext').write_text('subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\n')
    openssl('x509','-req','-in','server.csr','-CA','ca.pem','-CAkey','ca.key','-CAcreateserial','-out','server.pem','-days','1','-extfile','ext')
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(temp/'server.pem',temp/'server.key')
    ws,wss=Fixture(),Fixture(context)
    try:
        probe('ws fragmented text/binary',f'ws://127.0.0.1:{ws.port}/echo')
        probe('subprotocol',f'ws://127.0.0.1:{ws.port}/echo','protocol')
        for mode in ['reject','disconnect','invalid','flood','cancel','connecting-cancel']:
            probe(mode,f'ws://127.0.0.1:{ws.port}/{mode}',mode)
        probe('wss trusted CA',f'wss://localhost:{wss.port}/echo',env={'SSL_CERT_FILE':str(temp/'ca.pem')})
        probe('wss untrusted rejected',f'wss://localhost:{wss.port}/echo','reject',{'SSL_CERT_FILE':str(temp/'absent.pem')})
        probe('wss hostname rejected',f'wss://127.0.0.1:{wss.port}/echo','reject',{'SSL_CERT_FILE':str(temp/'ca.pem')})
        # Repeated independent connections check teardown/reconnect isolation.
        for index in range(12):probe(f'reconnect {index}',f'ws://127.0.0.1:{ws.port}/echo')
        if len(sys.argv)>2:
            run=subprocess.run([sys.argv[2],f'ws://127.0.0.1:{ws.port}'],capture_output=True,text=True,timeout=30)
            assert run.returncode==0,(run.stdout,run.stderr)
            results.append({'case':'same-session ws lifecycle and queue bounds','stdout':run.stdout.strip()})
            run=subprocess.run([sys.argv[2],f'wss://localhost:{wss.port}',str(temp/'ca.pem')],capture_output=True,text=True,timeout=40)
            assert run.returncode==0,(run.stdout,run.stderr)
            results.append({'case':'same-session wss lifecycle and explicit CA','stdout':run.stdout.strip()})
        if len(sys.argv)>3:
            stall=socket.socket();stall.bind(('127.0.0.1',0));stall.listen()
            done=threading.Event()
            def serve_stall():
                while not done.is_set():
                    try:c,_=stall.accept()
                    except OSError:return
                    def hold(connection):
                        done.wait(3);connection.close()
                    threading.Thread(target=hold,args=(c,),daemon=True).start()
            threading.Thread(target=serve_stall,daemon=True).start()
            try:
                for scheme in ['ws','wss']:
                    run=subprocess.run([sys.argv[3],f'{scheme}://127.0.0.1:{stall.getsockname()[1]}'],capture_output=True,text=True,timeout=10)
                    assert run.returncode==0,(scheme,run.stdout,run.stderr)
                    results.append({'case':scheme+' real stalled handshake timeout','stdout':run.stdout.strip()})
            finally:done.set();stall.close()
        assert ws.pongs>=13,(ws.pongs,'wire pongs not observed')
        print(json.dumps({'results':results,'wire_pongs':ws.pongs},ensure_ascii=False,indent=2))
    finally:ws.close();wss.close()

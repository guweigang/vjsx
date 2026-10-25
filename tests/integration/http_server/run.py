import pathlib,subprocess,time,json,http.client,socket,struct,os,base64,sys,tempfile
source=pathlib.Path(__file__).with_name('server.mjs');root=pathlib.Path(tempfile.mkdtemp(prefix='vjsx-http-acceptance-')); ep=root/'endpoint.json'
ep.unlink(missing_ok=True)
log=(root/'run.log').open('w');p=subprocess.Popen([sys.argv[1],'run','--runtime','node',str(source),str(ep)],stdout=log,stderr=log)
def frame(data,op=1,fin=True,mask=True):
 data=data.encode() if isinstance(data,str) else data
 out=bytes([(128 if fin else 0)|op]);n=len(data)
 out+=bytes([(128 if mask else 0)|n]) if n<126 else bytes([(128 if mask else 0)|126])+struct.pack('!H',n)
 if mask:
  key=b'abcd';out+=key;data=bytes(b^key[i%4] for i,b in enumerate(data))
 return out+data
def read_frame(s):
 def take(n):
  b=b''
  while len(b)<n:
   c=s.recv(n-len(b));assert c,'unexpected EOF';b+=c
  return b
 h=take(2);n=h[1]&127
 if n==126:n=struct.unpack('!H',take(2))[0]
 if n==127:n=struct.unpack('!Q',take(8))[0]
 assert h[1]&128==0
 return h[0]&15,take(n)
def ws(port,key=None):
 s=socket.create_connection(('127.0.0.1',port),timeout=10);key=key or base64.b64encode(os.urandom(16)).decode()
 s.sendall(f'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
 h=b''
 while b'\r\n\r\n' not in h:
  c=s.recv(1)
  if not c:break
  h+=c
 return s,h
try:
 for i in range(150):
  if ep.exists():break
  if p.poll() is not None:raise Exception('server exited')
  time.sleep(.1)
 assert ep.exists(),'no endpoint'
 port=json.loads(ep.read_text())['port']
 for method,body in [('POST','员工反馈 <原文> &'),('GET',None)]:
  c=http.client.HTTPConnection('127.0.0.1',port,timeout=10);b=body.encode() if body else None;c.request(method,'/test',body=b,headers={'Content-Type':'application/json'});r=c.getresponse();data=json.loads(r.read());assert r.status==200 and data['method']==method and data['body']==(body or '');c.close()
 raw=socket.create_connection(('127.0.0.1',port),timeout=10)
 raw.sendall(b'GET /raw HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: native-echo\r\n\r\nfirst')
 header=b''
 while not header.endswith(b'\r\n\r\n'):header+=raw.recv(1)
 assert header.startswith(b'HTTP/1.1 101')
 def raw_take(n):
  data=b''
  while len(data)<n:
   chunk=raw.recv(n-len(data));assert chunk;data+=chunk
  return data
 assert raw_take(5)==b'first'
 raw.sendall(b'second');assert raw_take(6)==b'second';raw.close()
 s,h=ws(port);assert h.startswith(b'HTTP/1.1 101'),h
 s.sendall(frame('员工'));assert read_frame(s)==(1,'echo:员工'.encode())
 s.sendall(frame('分',fin=False)+frame('片',op=0));assert read_frame(s)==(1,'echo:分片'.encode())
 s.sendall(frame(b'ping',op=9));assert read_frame(s)==(10,b'ping')
 s.sendall(frame(bytes(range(256)),op=2));assert read_frame(s)==(2,bytes(range(256)))
 s.sendall(frame(b'\x03\xe8',op=8));assert read_frame(s)==(8,b'\x03\xe8');s.close()
 s,h=ws(port);s.sendall(frame('please-close'));assert read_frame(s)==(8,b'\x0b\xb8done');s.sendall(frame(b'\x0b\xb8done',op=8));assert s.recv(1)==b'';s.close()
 s,h=ws(port);s.sendall(frame('invalid',mask=False));op,data=read_frame(s);assert op==8 and data==b'\x03\xea';s.close()
 s,h=ws(port,'bad-key');assert not h.startswith(b'HTTP/1.1 101');s.close()
 c=http.client.HTTPConnection('127.0.0.1',port,timeout=10);c.request('GET','/stop');assert c.getresponse().read()==b'bye';c.close()
 assert p.wait(timeout=10)==0
 print('PASS HTTP GET/POST UTF-8, RFC6455 upgrade/text/binary/fragments/ping/close, malformed frame and key rejection, listener cleanup')
finally:
 if p.poll() is None:p.kill();p.wait()
 log.close()

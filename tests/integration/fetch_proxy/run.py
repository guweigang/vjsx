import pathlib,http.server,threading,subprocess,os,tempfile,json,sys,shutil
class Handler(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def do_CONNECT(self):
  self.server.connects.append(self.path);self.send_response(200);self.end_headers();self.close_connection=False;self.handle_one_request()
 def log_message(self,*a):pass
 def do_GET(self):
  self.server.paths.append(self.path);b=b'{"ok":true}';self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
a=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);a.paths=[];a.connects=[];b=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);b.paths=[];b.connects=[]
for s in [a,b]:threading.Thread(target=s.serve_forever,daemon=True).start()
r=pathlib.Path(tempfile.mkdtemp(prefix='vjsx-proxy-'));p=r/'probe.mjs';p.write_text('for(const url of ["http://unresolvable.invalid/native",'+json.dumps('http://127.0.0.1:'+str(b.server_port)+'/direct')+']){const r=await fetch(url);if(!(await r.json()).ok)throw Error("failed");}console.log("PROXY_OK");')
env={**os.environ,'http_proxy':'http://127.0.0.1:'+str(a.server_port),'NO_PROXY':'127.0.0.1,localhost','no_proxy':'127.0.0.1,localhost'}
try:
 result=subprocess.run([sys.argv[1],'run','--runtime','node',str(p)],env=env,capture_output=True,text=True,timeout=20);assert result.returncode==0 and 'PROXY_OK' in result.stdout,(result.stdout,result.stderr)
 assert a.connects==['unresolvable.invalid:80'] and len(a.paths)==1 and a.paths[0].endswith('/native'),(a.connects,a.paths)
 assert b.paths==['/direct'],b.paths
 print('PASS native V proxy reaches unresolvable origin; NO_PROXY bypasses proxy for loopback')
finally:
 for s in [a,b]:s.shutdown();s.server_close()
 shutil.rmtree(r)

#!/usr/bin/env python3
"""Build and validate one locked browser graph under Node and packaged vjsx."""
import contextlib, http.server, io, json, os, pathlib, subprocess, sys, tempfile, threading
from fixture import Handler
root=pathlib.Path(__file__).resolve().parents[3]
folder=pathlib.Path(__file__).resolve().parent
cli=pathlib.Path(sys.argv[1]).resolve()
subprocess.run(['node',str(folder/'build.cjs')],check=True)
log=io.StringIO();runs=[]
env={**os.environ,'VJSX_ASSET_ROOT':str(root)}

def run(label,args,expect=True):
    result=subprocess.run(args,capture_output=True,text=True,env=env,timeout=90)
    assert result.returncode==0,(label,result.stdout,result.stderr)
    if expect:
        for marker in ['SATORI_CONSTRUCT lark function','SATORI_EVENT fixture-command','SATORI_STOP']:
            assert marker in result.stdout,(label,marker,result.stdout,result.stderr)
        assert not result.stderr,(label,result.stderr)
    runs.append({'case':label,'stdout':result.stdout.strip()})

with contextlib.redirect_stdout(log):
    server=http.server.ThreadingHTTPServer(('127.0.0.1',18881),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        run('Node same browser graph',['node',str(folder/'probe.bundle.mjs')])
        with tempfile.TemporaryDirectory(prefix='vjsx-satori-') as temp:
            artifact=str(pathlib.Path(temp)/'satori.vjsx');native=str(pathlib.Path(temp)/'satori-native')
            run('CLI compile bundle',[str(cli),'compile','--bundle',str(folder/'probe.bundle.mjs'),'-o',artifact],False)
            run('CLI packaged .vjsx',[str(cli),'run',artifact])
            run('CLI build native app',[str(cli),'build',str(folder/'probe.bundle.mjs'),'-o',native],False)
            # Native application runs with no Node or Python invocation.
            run('native executable',[native])
    finally:server.shutdown();server.server_close();thread.join()
wire=log.getvalue()
assert wire.count('FIXTURE_PROTOBUF_ACK')==3,wire
assert wire.count('FIXTURE_WIRE_PONG')==3,wire
print(json.dumps({'runs':runs,'fixture_log':wire.splitlines()},ensure_ascii=False,indent=2))

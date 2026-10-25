import pathlib,subprocess,sys
probe=pathlib.Path(__file__).with_name('probe.mjs')
r=subprocess.run([sys.argv[1],'run','--runtime','node',str(probe)],capture_output=True,text=True,timeout=5)
assert r.returncode==0,(r.stdout,r.stderr)
assert 'PASS top-level await' in r.stdout,r.stdout
print(r.stdout.strip())

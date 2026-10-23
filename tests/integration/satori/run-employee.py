#!/usr/bin/env python3
"""Require real SDK replies and proactive sends to carry valid Feishu query IDs."""
import contextlib
import http.server
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading
from employee_fixture import Handler

folder = pathlib.Path(__file__).resolve().parent
cli = pathlib.Path(sys.argv[1]).resolve()
env = {**os.environ, 'SATORI_PROBE': 'employee-probe.mjs'}
# Exercise embedded runtime assets, including the generated native application.
env.pop('VJSX_ASSET_ROOT', None)
subprocess.run(['node', str(folder / 'build.cjs')], check=True, env=env)
bundle = str(folder / 'employee-probe.bundle.mjs')
runs = []
wire = io.StringIO()

def execute(args):
    result = subprocess.run(args, capture_output=True, text=True, env=env, timeout=90)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result

def check(label, args):
    Handler.sent = []
    Handler.acks = 0
    result = execute(args)
    assert 'EMPLOYEE_STOP 2' in result.stdout, (label, result.stdout, result.stderr)
    assert not result.stderr, (label, result.stderr)
    assert len(Handler.sent) == 3, (label, Handler.sent)
    by_target = {item['body']['receive_id']: item for item in Handler.sent}
    for index in [1, 2]:
        item = by_target[f'oc_employee_{index}']
        assert item['query'] == {'receive_id_type': ['chat_id']}, item
        assert item['body']['msg_type'] == 'post', item
        assert json.loads(item['body']['content']) == {'zh_cn': {'content': [[{'tag': 'md', 'text': f'ACK:employee-report-{index}'}]]}}, item
    item = by_target['ou_employee_1']
    assert item['query'] == {'receive_id_type': ['open_id']}, item
    assert json.loads(item['body']['content']) == {'zh_cn': {'content': [[{'tag': 'md', 'text': 'TASK:follow-up-customer'}]]}}, item
    assert Handler.acks == 2, (label, Handler.acks)
    runs.append({'case': label, 'stdout': result.stdout, 'requests': Handler.sent, 'acks': Handler.acks})

with contextlib.redirect_stdout(wire):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18882), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        check('Node same browser graph', ['node', bundle])
        check('vjsx source', [str(cli), 'run', '--module', '--runtime', 'node', bundle])
        with tempfile.TemporaryDirectory(prefix='vjsx-employee-') as temp:
            artifact = str(pathlib.Path(temp) / 'employee.vjsx')
            native = str(pathlib.Path(temp) / 'employee-native')
            execute([str(cli), 'compile', '--bundle', bundle, '-o', artifact])
            check('packaged .vjsx', [str(cli), 'run', artifact])
            execute([str(cli), 'build', bundle, '-o', native])
            check('native executable', [native])
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
print(json.dumps({'runs': runs, 'fixture_log': wire.getvalue().splitlines()}, ensure_ascii=False, indent=2))

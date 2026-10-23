"""Local Feishu gateway and strict message-send API for the real Satori SDK."""
import base64, hashlib, http.server, json, struct, threading, time, urllib.parse
from fixture import frame, wsframe, read

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    sent = []
    acks = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.respond(None)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.respond(json.loads(raw) if raw else {})

    def respond(self, request):
        path = urllib.parse.urlsplit(self.path).path
        if self.headers.get('Upgrade', '').lower() == 'websocket':
            accept = base64.b64encode(hashlib.sha1((self.headers['Sec-WebSocket-Key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            self.send_response(101)
            self.send_header('Upgrade', 'websocket')
            self.send_header('Connection', 'Upgrade')
            self.send_header('Sec-WebSocket-Accept', accept)
            self.end_headers()
            self.wfile.flush()
            self.connection.settimeout(8)
            sent = False
            try:
                while True:
                    op, n = read(self.connection, 2)
                    masked = n & 128
                    n &= 127
                    if n == 126:
                        n = struct.unpack('!H', read(self.connection, 2))[0]
                    if n == 127:
                        n = struct.unpack('!Q', read(self.connection, 8))[0]
                    mask = read(self.connection, 4) if masked else b''
                    body = read(self.connection, n)
                    if masked:
                        body = bytes((v ^ mask[i % 4] for i, v in enumerate(body)))
                    op &= 15
                    if op == 2 and b'ping' in body and (not sent):
                        self.connection.sendall(wsframe(2, frame('pong')))
                        for index in [1, 2]:
                            event = {'schema': '2.0', 'header': {'event_id': f'ev_employee_{index}', 'event_type': 'im.message.receive_v1', 'app_id': 'fixture-app', 'tenant_key': 'fixture-tenant'}, 'event': {'sender': {'sender_id': {'open_id': f'ou_employee_{index}'}, 'sender_type': 'user'}, 'message': {'message_id': f'om_in_{index}', 'chat_id': f'oc_employee_{index}', 'chat_type': 'p2p', 'message_type': 'text', 'create_time': str(int(time.time() * 1000)), 'content': json.dumps({'text': f'employee-report-{index}'})}}}
                            self.connection.sendall(wsframe(2, frame('event', json.dumps(event).encode(), 1)))
                        sent = True
                    elif op == 2 and b'biz_rt' in body and (b'200' in body):
                        Handler.acks += 1
                    elif op == 8:
                        self.connection.sendall(wsframe(8, body))
                        break
            except (EOFError, OSError, TimeoutError):
                pass
            self.close_connection = True
            return
        if path == '/callback/ws/endpoint':
            response = {'code': 0, 'data': {'URL': 'ws://127.0.0.1:18882/gateway?device_id=fixture&service_id=1', 'ClientConfig': {'PingInterval': 60}}}
        elif path.endswith('/auth/v3/tenant_access_token/internal'):
            assert request == {'app_id': 'fixture-app', 'app_secret': 'fixture-secret'}, request
            response = {'code': 0, 'tenant_access_token': 'fixture-token', 'expire': 3600}
        elif path.endswith('/bot/v3/info'):
            response = {'code': 0, 'bot': {'open_id': 'fixture-bot', 'app_name': 'Fixture', 'avatar_url': ''}}
        elif path == '/open-apis/im/v1/messages':
            index = len(Handler.sent) + 1
            Handler.sent.append({'query': urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query), 'body': request})
            expected = 'chat_id' if request['receive_id'].startswith('oc_') else 'open_id'
            if Handler.sent[-1]['query'] != {'receive_id_type': [expected]}:
                response = {'code': 99992402, 'msg': 'Missing or invalid receive_id_type'}
            else:
                response = {'code': 0, 'data': {'message_id': f'om_out_{index}', 'create_time': str(int(time.time())), 'sender': {'id': 'fixture-bot'}}}
        else:
            raise AssertionError('Unexpected API ' + self.path)
        payload = json.dumps(response).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

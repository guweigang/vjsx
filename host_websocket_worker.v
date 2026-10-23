module vjsx

import crypto.rand
import crypto.sha1
import encoding.base64
import net.urllib
import time

fn websocket_frame(opcode u8, payload []u8) ![]u8 {
	mask := rand.bytes(4)!
	mut out := [u8(0x80) | opcode]
	if payload.len < 126 {
		out << u8(0x80) | u8(payload.len)
	} else if payload.len <= 65535 {
		out << [u8(0xfe), u8(payload.len >> 8), u8(payload.len)]
	} else {
		out << u8(0xff)
		for shift := 56; shift >= 0; shift -= 8 { out << u8(u64(payload.len) >> shift) }
	}
	out << mask
	for i, b in payload { out << b ^ mask[i % 4] }
	return out
}

fn websocket_worker(mut worker WebSocketWorker, raw string, protocols string) {
	mut io := WebSocketIO{ worker: worker, wake: worker.command_read, timeout_ms: worker.config.io_timeout_ms }
	defer {
		io.dispose()
	}
	websocket_run(mut worker, mut io, raw, protocols) or {
		worker.guard.lock()
		stopped := worker.stopped
		worker.guard.unlock()
		if !stopped {
			worker.emit(WebSocketEvent{ kind: 'error', text: err.msg() })
		}
		worker.emit(WebSocketEvent{ kind: 'close', code: 1006 })
	}
}

fn websocket_run(mut worker WebSocketWorker, mut io WebSocketIO, raw string, protocols string) ! {
	uri := urllib.parse(raw)!
	host := uri.hostname()
	port := if uri.port() != '' {
		uri.port()
	} else if uri.scheme == 'wss' {
		'443'
	} else {
		'80'
	}
	deadline := time.now().unix_milli() + worker.config.connect_timeout_ms
	io.connect(host, port, uri.scheme == 'wss', worker.config.ca_file, deadline)!
	nonce := rand.bytes(16)!
	key := base64.encode(nonce)
	resource := if uri.path == '' { '/' } else { uri.path }
	query := if uri.raw_query == '' { '' } else { '?' + uri.raw_query }
	protocol_header := if protocols == '' { '' } else { 'Sec-WebSocket-Protocol: ${protocols}\r\n' }
	io.write('GET ${resource}${query} HTTP/1.1\r\nHost: ${uri.host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n${protocol_header}\r\n'.bytes())!
	mut incoming := []u8{}
	mut buffer := []u8{len: 16384}
	mut header_end := -1
	for header_end < 0 {
		left := int(deadline - time.now().unix_milli())
		if left <= 0 { return error('WebSocket upgrade timed out') }
		io.wait(false, left)!
		n := io.read(mut buffer, deadline)!
		if n <= 0 { return error('WebSocket peer closed during upgrade') }
		incoming << buffer[..n]
		header_end = incoming.bytestr().index('\r\n\r\n') or { -1 }
		if (header_end < 0 && incoming.len > 16384) || header_end > 16384 {
			return error('WebSocket upgrade headers too large')
		}
	}
	headers := incoming[..header_end].bytestr().split('\r\n')
	if headers[0].split(' ').len < 2 || headers[0].split(' ')[1] != '101' {
		return error('WebSocket upgrade requires HTTP 101')
	}
	mut fields := map[string]string{}
	for line in headers[1..] {
		pieces := line.split_nth(':', 2)
		if pieces.len != 2 { return error('invalid WebSocket upgrade header') }
		name := pieces[0].to_lower()
		if name in fields { return error('duplicate WebSocket upgrade header') }
		fields[name] = pieces[1].trim_space()
	}
	expected := base64.encode(sha1.sum((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').bytes()))
	if fields['sec-websocket-accept'] != expected || fields['upgrade'].to_lower() != 'websocket'
		|| 'upgrade' !in fields['connection'].to_lower().split(',').map(it.trim_space())
		|| fields['sec-websocket-extensions'] != '' {
		return error('invalid WebSocket upgrade response')
	}
	selected := fields['sec-websocket-protocol']
	if selected != '' && selected !in protocols.split(',').map(it.trim_space()) {
		return error('unrequested WebSocket subprotocol')
	}
	if protocols != '' && selected == '' {
		return error('server did not select a WebSocket subprotocol')
	}
	incoming = incoming[header_end + 4..].clone()
	if !worker.emit(WebSocketEvent{ kind: 'open', text: selected }) { return }
	mut decoder := WebSocketFrameDecoder{ max_message_bytes: worker.config.max_message_bytes }
	mut closing := false
	mut close_deadline := i64(0)
	for {
		worker.guard.lock()
		C.vjsx_ws_drain(worker.command_read)
		stopped := worker.stopped || worker.cancel_requested
		commands := worker.commands.clone()
		worker.commands = []WebSocketEvent{}
		worker.command_bytes = 0
		worker.guard.unlock()
		if stopped { return error('WebSocket cancelled') }
		for command in commands {
			if closing { continue }
			if command.kind == 'close' {
				payload := [u8(command.code >> 8), u8(command.code)]
				mut body := payload.clone()
				body << command.bytes
				io.write(websocket_frame(8, body)!)!
				closing = true
				close_deadline = time.now().unix_milli() + worker.config.io_timeout_ms
			} else {
				io.write(websocket_frame(if command.kind == 'text' { u8(1) } else { u8(2) }, command.bytes)!)!
				if !worker.emit(WebSocketEvent{ kind: 'sent', code: command.bytes.len }) { return }
			}
		}
		for incoming.len > 0 {
			frame := decoder.decode(mut incoming)
			if frame.kind == .need_more { break }
			if frame.kind == .failure {
				io.write(websocket_frame(8, [u8(frame.close_code >> 8), u8(frame.close_code)])!) or {}
				return error(frame.reason)
			}
			if frame.kind == .message && !closing {
				if !worker.emit(WebSocketEvent{
					kind:  if frame.opcode == .text {
						'text'
					} else {
						'binary'
					}
					bytes: frame.payload.clone()
				}) {
					return
				}
			} else if frame.kind == .control {
				if frame.opcode == .ping { io.write(websocket_frame(10, frame.payload)!)! }
				if frame.opcode == .close {
					if !closing { io.write(websocket_frame(8, frame.payload)!)! }
					code := if frame.payload.len >= 2 {
						int(frame.payload[0]) << 8 | int(frame.payload[1])
					} else {
						1005
					}
					reason := if frame.payload.len >= 2 { frame.payload[2..].bytestr() } else { '' }
					worker.emit(WebSocketEvent{ kind: 'close', code: code, text: reason, clean: true })
					return
				}
			}
			incoming = incoming[frame.consumed..].clone()
		}
		timeout := if closing { int(close_deadline - time.now().unix_milli()) } else { -1 }
		if closing && timeout <= 0 { return error('WebSocket close handshake timed out') }
		if !isnil(io.tls) && C.SSL_pending(io.tls.ssl) > 0 {
			// Process buffered TLS records without waiting on the underlying socket.
		} else {
			ready := C.vjsx_ws_wait(io.tcp.sock.handle, worker.command_read, 0, timeout)
			if ready == 4 { continue }
			if ready & 2 != 0 { continue }
			if ready <= 0 { return error('WebSocket readiness wait failed or close timed out') }
		}
		n := io.read(mut buffer, time.now().unix_milli() + io.timeout_ms)!
		if n <= 0 { return error('WebSocket peer disconnected without close') }
		incoming << buffer[..n]
		if incoming.len > worker.config.max_message_bytes + 16398 {
			return error('WebSocket input buffer limit exceeded')
		}
	}
}

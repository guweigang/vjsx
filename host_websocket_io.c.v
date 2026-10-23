module vjsx

import net
import net.openssl
import time

#include "@VMODROOT/native/websocket_io.h"

fn C.vjsx_ws_pair(&i32) int
fn C.vjsx_ws_signal(int)
fn C.vjsx_ws_drain(int)
fn C.vjsx_ws_close(int) int
fn C.vjsx_ws_nonblock(int)
fn C.vjsx_ws_wait(int, int, int, int) int
fn C.vjsx_ws_tls_identity(voidptr, &char) int
fn C.vjsx_ws_plain_io(int, voidptr, int, int) int
fn C.vjsx_ws_connect_start(int, voidptr, u32) int
fn C.vjsx_ws_connect_status(int) int
fn C.vjsx_ws_tls_start(voidptr, int, &char) int
fn C.ERR_clear_error()
fn C.SSL_connect(voidptr) int
fn C.SSL_get_verify_result(voidptr) int
fn C.SSL_read(voidptr, voidptr, int) int
fn C.SSL_write(voidptr, voidptr, int) int
fn C.SSL_get_error(voidptr, int) int
fn C.SSL_pending(voidptr) int

struct WebSocketIO {
mut:
	tcp        &net.TcpConn     = unsafe { nil }
	tls        &openssl.SSLConn = unsafe { nil }
	wake       int
	timeout_ms int
	worker     &WebSocketWorker = unsafe { nil }
}

fn (mut io WebSocketIO) dispose() {
	if !isnil(io.tls) { io.tls.shutdown() or {} }
	if !isnil(io.tcp) { io.tcp.close() or {} }
}

fn (mut io WebSocketIO) read(mut bytes []u8, deadline i64) !int {
	for {
		remaining := int(deadline - time.now().unix_milli())
		if remaining <= 0 { return error('WebSocket read timed out') }
		C.ERR_clear_error()
		n := if isnil(io.tls) {
			C.vjsx_ws_plain_io(io.tcp.sock.handle, bytes.data, bytes.len, 0)
		} else {
			C.SSL_read(io.tls.ssl, bytes.data, bytes.len)
		}
		if n > 0 { return n }
		if isnil(io.tls) {
			if n == 0 { return 0 }
			if n != -2 { return error('WebSocket read failed') }
			io.wait(false, remaining)!
		} else {
			code := C.SSL_get_error(io.tls.ssl, n)
			if code !in [2, 3] { return error('TLS read failed or peer closed connection') }
			io.wait(code == 3, remaining)!
		}
	}
	return 0
}

fn (mut io WebSocketIO) wait(writing bool, timeout_ms int) ! {
	if !writing && !isnil(io.tls) && C.SSL_pending(io.tls.ssl) > 0 { return }
	deadline := if timeout_ms < 0 { i64(-1) } else { time.now().unix_milli() + timeout_ms }
	for {
		remaining := if deadline < 0 { -1 } else { int(deadline - time.now().unix_milli()) }
		if deadline >= 0 && remaining <= 0 { return error('WebSocket I/O timed out') }
		ready := C.vjsx_ws_wait(io.tcp.sock.handle, io.wake, int(writing), remaining)
		if ready == 4 { continue }
		if ready & 2 != 0 {
			io.worker.guard.lock()
			stopped := io.worker.stopped || io.worker.cancel_requested
			C.vjsx_ws_drain(io.wake)
			io.worker.guard.unlock()
			if stopped { return error('WebSocket cancelled') }
			continue
		}
		if ready < 0 { return error('WebSocket readiness wait failed') }
		if ready == 0 { return error('WebSocket I/O timed out') }
		return
	}
}

fn (mut io WebSocketIO) write(bytes []u8) ! {
	mut offset := 0
	deadline := time.now().unix_milli() + io.timeout_ms
	for offset < bytes.len {
		remaining := int(deadline - time.now().unix_milli())
		if remaining <= 0 { return error('WebSocket write timed out') }
		C.ERR_clear_error()
		ptr := unsafe { &u8(bytes.data) + offset }
		n := if isnil(io.tls) {
			C.vjsx_ws_plain_io(io.tcp.sock.handle, ptr, bytes.len - offset, 1)
		} else {
			C.SSL_write(io.tls.ssl, ptr, bytes.len - offset)
		}
		if n > 0 {
			offset += n
			continue
		}
		if isnil(io.tls) {
			if n != -2 { return error('WebSocket write failed') }
			io.wait(true, remaining)!
		} else {
			code := C.SSL_get_error(io.tls.ssl, n)
			if code !in [2, 3] { return error('TLS write failed') }
			io.wait(code == 3, remaining)!
		}
	}
}

// One deadline covers TCP attempts, TLS and HTTP upgrade. The OS resolver is
// synchronous; elapsed resolver time counts against the deadline after return.
fn (mut io WebSocketIO) connect(host string, port string, secure bool, ca_file string, deadline i64) ! {
	address := if host.contains(':') { '[${host}]:${port}' } else { '${host}:${port}' }
	addresses := net.resolve_addrs(address, .unspec, .tcp)!
	mut connected := false
	for addr in addresses {
		remaining := int(deadline - time.now().unix_milli())
		if remaining <= 0 { return error('WebSocket connect timed out') }
		sock := net.new_tcp_socket(addr.family())!
		io.tcp = &net.TcpConn{ sock: sock, is_blocking: false }
		C.vjsx_ws_nonblock(sock.handle)
		status := C.vjsx_ws_connect_start(sock.handle, voidptr(&addr), addr.len())
		if status == 1 {
			io.wait(true, remaining) or {
				io.tcp.close() or {}
				io.tcp = unsafe { nil }
				return err
			}
		}
		if status >= 0 && C.vjsx_ws_connect_status(sock.handle) == 0 {
			connected = true
			break
		}
		io.tcp.close() or {}
		io.tcp = unsafe { nil }
	}
	if !connected { return error('WebSocket TCP connect failed') }
	io.tcp.set_read_timeout(io.timeout_ms * time.millisecond)
	io.tcp.set_write_timeout(io.timeout_ms * time.millisecond)
	if !secure { return }
	io.tls = openssl.new_ssl_conn(validate: true, verify: ca_file)!
	io.tls.handle = io.tcp.sock.handle
	if C.vjsx_ws_tls_identity(io.tls.ssl, &char(host.str)) != 1
		|| C.vjsx_ws_tls_start(io.tls.ssl, io.tcp.sock.handle, &char(host.str)) != 1 {
		return error('TLS identity setup failed')
	}
	for {
		remaining := int(deadline - time.now().unix_milli())
		if remaining <= 0 { return error('WebSocket TLS handshake timed out') }
		C.ERR_clear_error()
		n := C.SSL_connect(io.tls.ssl)
		if n == 1 {
			if C.SSL_get_verify_result(io.tls.ssl) != 0 {
				return error('TLS certificate verification failed')
			}
			return
		}
		code := C.SSL_get_error(io.tls.ssl, n)
		if code !in [2, 3] {
			return error('TLS handshake failed (certificate, hostname, or peer failure)')
		}
		io.wait(code == 3, remaining)!
	}
}

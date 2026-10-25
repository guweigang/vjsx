// Adapted from V net.websocket frame_decoder.v, MIT (V contributors),
// source revision e21021d10433ad9fa7fd45fd63e2dee79ec612ef. Client/server framing.
module vjsx

import encoding.utf8

// WebSocketFrameDecodeKind distinguishes an incomplete frame, an intermediate fragment,
// a complete message, a control frame, and a terminal protocol error.
enum WebSocketFrameDecodeKind {
	need_more
	fragment
	message
	control
	failure
}

// WebSocketDecodedFrame borrows payload from the input or decoder until the next decode
// call. consumed bytes may be discarded only after the payload has been used.
// A failure carries a WebSocket close code and reason, not a consumed payload.
struct WebSocketDecodedFrame {
pub:
	kind       WebSocketFrameDecodeKind
	consumed   int
	opcode     WebSocketOpcode = .continuation
	payload    []u8
	close_code int
	reason     string
}

// WebSocketFrameDecoder incrementally decodes server frames, or masked client
// frames when expect_mask is enabled, without socket I/O. Keep incomplete input and append more bytes before retrying decode.
// One instance belongs to one connection and must not be shared concurrently.
struct WebSocketFrameDecoder {
pub:
	max_message_bytes int = 16384
	expect_mask       bool
mut:
	fragment        []u8
	fragment_opcode u8
	fragment_done   bool
	text_state      WebSocketFrameUtf8
	failure_code    int
	failure_reason  string
}

struct WebSocketFrameUtf8 {
mut:
	remaining int
	lower     u8 = 0x80
	upper     u8 = 0xbf
}

// Check each fragment immediately, retaining only the unfinished rune state.
fn (mut state WebSocketFrameUtf8) accept(bytes []u8) bool {
	for byte in bytes {
		if state.remaining > 0 {
			if byte < state.lower || byte > state.upper { return false }
			state.remaining--
			state.lower = 0x80
			state.upper = 0xbf
		} else if byte < 0x80 {
			continue
		} else if byte >= 0xc2 && byte <= 0xdf {
			state.remaining = 1
		} else if byte >= 0xe0 && byte <= 0xef {
			state.remaining = 2
			if byte == 0xe0 { state.lower = 0xa0 }
			if byte == 0xed { state.upper = 0x9f }
		} else if byte >= 0xf0 && byte <= 0xf4 {
			state.remaining = 3
			if byte == 0xf0 { state.lower = 0x90 }
			if byte == 0xf4 { state.upper = 0x8f }
		} else {
			return false
		}
	}
	return true
}

fn websocket_close_code_valid(code int) bool {
	return code in [1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014]
		|| (code >= 3000 && code <= 4999)
}

fn (mut decoder WebSocketFrameDecoder) fail(code int, reason string) WebSocketDecodedFrame {
	decoder.failure_code = code
	decoder.failure_reason = reason
	return WebSocketDecodedFrame{ kind: .failure, close_code: code, reason: reason }
}

// decode consumes at most one complete frame. It checks declared lengths before
// allocation, combines fragments, and checks
// UTF-8, close payloads, reserved bits/opcodes, and canonical lengths. Incomplete
// input is not modified. An error is terminal: create a new decoder to reset it.
fn (mut decoder WebSocketFrameDecoder) decode(mut input []u8) WebSocketDecodedFrame {
	if decoder.failure_code != 0 {
		return WebSocketDecodedFrame{ kind: .failure, close_code: decoder.failure_code, reason: decoder.failure_reason }
	}
	if decoder.max_message_bytes < 1 {
		return decoder.fail(1009, 'Invalid message limit')
	}
	if decoder.fragment_done {
		decoder.fragment.clear()
		decoder.fragment_done = false
	}
	if input.len < 2 { return WebSocketDecodedFrame{} }
	first, second := input[0], input[1]
	opcode := first & 15
	fin := first & 128 != 0
	if first & 112 != 0 || (second & 128 != 0) != decoder.expect_mask || opcode !in [
		u8(0),
		1,
		2,
		8,
		9,
		10,
	]
		|| (opcode >= 8 && (!fin || second & 127 > 125)) {
		return decoder.fail(1002, 'Invalid frame header')
	}
	mut length := u64(second & 127)
	extra := if length == 126 {
		2
	} else if length == 127 {
		8
	} else {
		0
	}
	if input.len < 2 + extra { return WebSocketDecodedFrame{} }
	if extra > 0 {
		length = 0
		for i in 0 .. extra { length = (length << 8) | input[2 + i] }
		if (extra == 2 && length < 126) || (extra == 8 && (length <= 65535 || length >> 63 != 0)) {
			return decoder.fail(1002, 'Noncanonical frame length')
		}
	}
	if opcode < 8 {
		if (opcode == 0 && decoder.fragment_opcode == 0)
			|| (opcode != 0 && decoder.fragment_opcode != 0) {
			return decoder.fail(1002, 'Invalid continuation')
		}
		if length > u64(decoder.max_message_bytes - decoder.fragment.len) {
			return decoder.fail(1009, 'Message too large')
		}
	}
	header := 2 + extra + if decoder.expect_mask { 4 } else { 0 }
	if input.len < header || length > u64(input.len - header) { return WebSocketDecodedFrame{} }
	end := header + int(length)
	// Both slices are contained in the complete, bounded input frame.
	mut payload := input[header..end].clone()
	if decoder.expect_mask {
		for i in 0 .. payload.len { payload[i] ^= input[header - 4 + i % 4] }
	}
	if opcode >= 8 {
		if opcode == 8 {
			if payload.len == 1 { return decoder.fail(1002, 'Invalid close payload') }
			if payload.len >= 2 {
				code := (int(payload[0]) << 8) | int(payload[1])
				if !websocket_close_code_valid(code) {
					return decoder.fail(1002, 'Invalid close code')
				}
				if !utf8.validate(unsafe { &u8(payload.data) + 2 }, payload.len - 2) {
					return decoder.fail(1007, 'Invalid close UTF-8')
				}
			}
		}
		return WebSocketDecodedFrame{ kind: .control, consumed: end, opcode: unsafe { WebSocketOpcode(opcode) }, payload: payload }
	}
	if fin && decoder.fragment_opcode == 0 {
		if opcode == 1 && !utf8.validate(payload.data, payload.len) {
			return decoder.fail(1007, 'Invalid text UTF-8')
		}
		return WebSocketDecodedFrame{ kind: .message, consumed: end, opcode: unsafe { WebSocketOpcode(opcode) }, payload: payload }
	}
	if opcode != 0 {
		decoder.fragment_opcode = opcode
		decoder.text_state = WebSocketFrameUtf8{}
	}
	if decoder.fragment_opcode == 1 {
		if !decoder.text_state.accept(payload) || (fin && decoder.text_state.remaining != 0) {
			return decoder.fail(1007, 'Invalid fragmented text UTF-8')
		}
	}
	decoder.fragment << payload
	if !fin { return WebSocketDecodedFrame{ kind: .fragment, consumed: end } }
	message_opcode := decoder.fragment_opcode
	decoder.fragment_opcode = 0
	decoder.fragment_done = true
	return WebSocketDecodedFrame{ kind: .message, consumed: end, opcode: unsafe { WebSocketOpcode(message_opcode) }, payload: decoder.fragment }
}

enum WebSocketOpcode {
	continuation = 0
	text         = 1
	binary       = 2
	close        = 8
	ping         = 9
	pong         = 10
}

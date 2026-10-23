module vjsx

fn test_websocket_decoder_fragment_control_and_limits() {
	mut decoder := WebSocketFrameDecoder{ max_message_bytes: 4 }
	mut first := [u8(1), 2, `h`, `i`]
	assert decoder.decode(mut first).kind == .fragment
	mut ping := [u8(0x89), 1, `p`]
	control := decoder.decode(mut ping)
	assert control.kind == .control && control.opcode == .ping
	mut last := [u8(0x80), 1, `!`]
	message := decoder.decode(mut last)
	assert message.kind == .message && message.payload.bytestr() == 'hi!'
	mut huge := [u8(0x82), 126, 0, 128]
	assert decoder.decode(mut huge).close_code == 1009
	mut invalid := WebSocketFrameDecoder{}
	mut masked := [u8(0x81), 0x80]
	assert invalid.decode(mut masked).close_code == 1002
	mut bad_utf8 := WebSocketFrameDecoder{}
	mut invalid_text := [u8(0x81), 1, 0xff]
	assert bad_utf8.decode(mut invalid_text).close_code == 1007
}

fn test_websocket_queue_reserves_terminal_and_fences_late_events() {
	mut worker := WebSocketWorker{
		config:        WebSocketConfig{ queue_capacity: 2, max_message_bytes: 4, max_queued_bytes: 4 }
		command_read:  -1
		command_write: -1
		notify_write:  -1
		ready_state:   &RuntimeHostStreamReadyState{}
	}
	assert worker.emit(WebSocketEvent{ kind: 'binary', bytes: [u8(1), 2] })
	assert worker.emit(WebSocketEvent{ kind: 'binary', bytes: [u8(3), 4] })
	assert !worker.emit(WebSocketEvent{ kind: 'binary', bytes: [u8(5)] })
	assert worker.events.len == 4
	assert worker.events[2].kind == 'error'
	assert worker.events[3].kind == 'close'
	assert !worker.emit(WebSocketEvent{ kind: 'open' })
	worker.stop()
	assert !worker.emit(WebSocketEvent{ kind: 'close' })
}

module vjsx

import sync

pub struct RuntimeHostStreamFrame {
pub:
	bytes []u8
}

struct RuntimeHostStreamState {
	guard &sync.Mutex = sync.new_mutex()
mut:
	capacity int
	frames   []RuntimeHostStreamFrame
	closed   bool
}

// RuntimeHostStreamMailbox is a minimal bounded host-stream protocol. Producers
// may run on background threads and use try_push(); the session-owning lane uses
// drain() to acknowledge capacity. A false push is backpressure, never a drop.
pub struct RuntimeHostStreamMailbox {
	state &RuntimeHostStreamState
}

pub fn new_runtime_host_stream_mailbox(capacity int) RuntimeHostStreamMailbox {
	return RuntimeHostStreamMailbox{
		state: &RuntimeHostStreamState{
			capacity: if capacity < 1 { 1 } else { capacity }
			frames: []RuntimeHostStreamFrame{}
		}
	}
}

pub fn (mailbox RuntimeHostStreamMailbox) try_push(bytes []u8) bool {
	mut state := mailbox.state
	state.guard.lock()
	defer {
		state.guard.unlock()
	}
	if state.closed || state.frames.len >= state.capacity {
		return false
	}
	state.frames << RuntimeHostStreamFrame{ bytes: bytes.clone() }
	return true
}

// Drain at most max_frames. Zero drains every currently accepted frame.
pub fn (mailbox RuntimeHostStreamMailbox) drain(max_frames int) []RuntimeHostStreamFrame {
	mut state := mailbox.state
	state.guard.lock()
	count := if max_frames <= 0 || max_frames > state.frames.len {
		state.frames.len
	} else {
		max_frames
	}
	mut frames := []RuntimeHostStreamFrame{cap: count}
	for _ in 0 .. count {
		frames << state.frames[0]
		state.frames.delete(0)
	}
	state.guard.unlock()
	return frames
}

pub fn (mailbox RuntimeHostStreamMailbox) pending() int {
	mut state := mailbox.state
	state.guard.lock()
	count := state.frames.len
	state.guard.unlock()
	return count
}

pub fn (mailbox RuntimeHostStreamMailbox) close() {
	mut state := mailbox.state
	state.guard.lock()
	state.closed = true
	state.frames = []RuntimeHostStreamFrame{}
	state.guard.unlock()
}

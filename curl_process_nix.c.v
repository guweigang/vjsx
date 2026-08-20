module vjsx

#include "vjsx_curl_process.h"

fn C.vjsx_curl_process_start(&char, &&char, &char, &int) int
fn C.vjsx_curl_process_poll(int, &int) int
fn C.vjsx_curl_process_signal(int, int) int
fn C.vjsx_curl_process_wait(int, &int) int

struct CurlProcess {
mut:
	pid       int
	exit_code int = -1
	done      bool
}

fn start_curl_process(path string, args []string, output_path string) !CurlProcess {
	mut argv := []&char{cap: args.len + 2}
	argv << &char(path.str)
	for arg in args {
		argv << &char(arg.str)
	}
	argv << &char(unsafe { nil })
	mut pid := 0
	if C.vjsx_curl_process_start(&char(path.str), argv.data, &char(output_path.str), &pid) != 0 {
		return error('failed to start curl')
	}
	return CurlProcess{
		pid: pid
	}
}

fn (mut process CurlProcess) poll() !bool {
	if process.done {
		return true
	}
	mut exit_code := -1
	status := C.vjsx_curl_process_poll(process.pid, &exit_code)
	if status < 0 {
		return error('failed to poll curl process')
	}
	if status == 0 {
		process.exit_code = exit_code
		process.done = true
		return true
	}
	return false
}

fn (mut process CurlProcess) terminate(force bool) {
	if process.done || process.pid <= 0 {
		return
	}
	C.vjsx_curl_process_signal(process.pid, if force { 1 } else { 0 })
}

fn (mut process CurlProcess) reap() {
	if process.done || process.pid <= 0 {
		return
	}
	mut exit_code := -1
	if C.vjsx_curl_process_wait(process.pid, &exit_code) == 0 {
		process.exit_code = exit_code
		process.done = true
	}
}

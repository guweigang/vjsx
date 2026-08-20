module vjsx

import os

struct CurlProcess {
mut:
	process     &os.Process = unsafe { nil }
	output_path string
	exit_code   int = -1
	done        bool
}

fn start_curl_process(path string, args []string, output_path string) !CurlProcess {
	mut process := os.new_process(path)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	return CurlProcess{
		process:     process
		output_path: output_path
	}
}

fn (mut process CurlProcess) poll() !bool {
	if process.done {
		return true
	}
	if process.process.is_alive() {
		return false
	}
	process.process.wait()
	output := process.process.stdout_slurp()
	os.write_file(process.output_path, output)!
	process.exit_code = process.process.code
	process.process.close()
	process.done = true
	return true
}

fn (mut process CurlProcess) terminate(force bool) {
	if process.done || isnil(process.process) {
		return
	}
	if force {
		process.process.signal_kill()
	} else {
		process.process.signal_term()
	}
}

fn (mut process CurlProcess) reap() {
	if process.done || isnil(process.process) {
		return
	}
	process.process.wait()
	output := process.process.stdout_slurp()
	os.write_file(process.output_path, output) or {}
	process.exit_code = process.process.code
	process.process.close()
	process.done = true
}

module main

import os

fn run_npm_curl(path string, args []string, diagnostics_path string) ! {
	mut process := os.new_process(path)
	process.set_args(args)
	process.wait()
	defer {
		process.close()
	}
	if process.code != 0 {
		diagnostics := os.read_file(diagnostics_path) or { '' }
		message := diagnostics.trim_space()
		if message != '' {
			return error(message)
		}
		return error('curl exited with code ${process.code}')
	}
}

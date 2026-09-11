module main

import os

#include "vjsx_curl_process.h"

fn C.vjsx_curl_process_start(&char, &&char, &char, &int) int

fn C.vjsx_curl_process_wait(int, &int) int

fn run_npm_curl(path string, args []string, diagnostics_path string) ! {
	mut argv := []&char{cap: args.len + 2}
	argv << &char(path.str)
	for arg in args {
		argv << &char(arg.str)
	}
	argv << &char(unsafe { nil })
	mut pid := 0
	if C.vjsx_curl_process_start(&char(path.str), argv.data, &char(diagnostics_path.str), &pid) != 0 {
		return error('could not start curl')
	}
	mut exit_code := -1
	if C.vjsx_curl_process_wait(pid, &exit_code) != 0 {
		return error('could not wait for curl')
	}
	if exit_code != 0 {
		diagnostics := os.read_file(diagnostics_path) or { '' }
		message := diagnostics.trim_space()
		if message != '' {
			return error(message)
		}
		return error('curl exited with code ${exit_code}')
	}
}

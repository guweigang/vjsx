module main

import os
import vjsx
import runtimejs

const cli_version = '0.0.1'

struct CliOptions {
	command          string
	script_file      string
	script_args      []string
	as_module        bool
	runtime_profile  string
	install_specs    []string
	install_registry string
	install_dev      bool
	list_depth       int = -1
	list_omit        []string
	list_json        bool
}

@[noreturn]
fn fail(message string) {
	eprintln(message)
	exit(1)
}

fn usage() {
	println(help_text())
}

fn version_text() string {
	return 'vjsx ${cli_version}\n'
}

fn help_text() string {
	return 'vjsx ${cli_version}

Usage:
  vjsx [run] [--module|-m] [--runtime|-r <node|script|browser>] <script.js> [args...]
  vjsx check [--module|-m] [--runtime|-r <node|script|browser>] <script.js> [args...]
  vjsx check-runtime [--runtime|-r <node|script|browser>]
  vjsx capabilities [--runtime|-r <node|script|browser>]
  vjsx install [--registry <url>] [--dev] [package[@version]...]
  vjsx repair [--registry <url>] [package...]
  vjsx ls [--json] [--depth <n>] [--omit=<dev|optional|peer>] [package...]
  vjsx list [--json] [--depth <n>] [--omit=<dev|optional|peer>] [package...]
  vjsx remove <package...>
  vjsx uninstall <package...>
  vjsx version
  vjsx help

Options:
  -h, --help       Show this help text
  -v, --version    Show the vjsx version
  -m, --module     Run input as an ES module
  -r, --runtime    Select host runtime profile: node, script, browser

Runtime profiles:
  node      Node-like host with process, Buffer, timers, fs/path/http/https/os,
            child_process, fetch, sqlite, and mysql when compiled in.
  script    Lighter script host with process, Buffer, URL, path, and
            node:timers/promises; no filesystem/network modules by default.
  browser   Browser-style module host with window/self, fetch, URL, timers,
            streams, Blob, FormData, Encoding, Intl, and Web Crypto.

Package commands:
  install   Install package.json dependencies and write npm-compatible package-lock.json.
  repair    Restore locked packages without changing dependency versions.
  ls        Print the installed dependency tree from package-lock.json and node_modules.
  remove    Remove top-level dependencies from package.json, package-lock.json, and node_modules.
'
}

fn read_env_script_args(args_file string) []string {
	if args_file == '' || !os.exists(args_file) {
		return []string{}
	}
	return os.read_lines(args_file) or { fail(err.msg()) }
}

fn validate_script_type(script_file string, as_module bool) bool {
	mut enable_module := as_module
	if script_file.ends_with('.mjs') || script_file.ends_with('.mts') {
		enable_module = true
		return enable_module
	}
	if script_file.ends_with('.js') || script_file.ends_with('.cjs') || script_file.ends_with('.ts')
		|| script_file.ends_with('.cts') {
		return enable_module
	}
	fail('unsupported script type: ${script_file}\nexpected a .js, .mjs, .cjs, .ts, .mts, or .cts file')
	return enable_module
}

fn parse_env_options() ?CliOptions {
	file := os.getenv('VJS_SCRIPT_FILE')
	args_file := os.getenv('VJS_ARGS_FILE')
	if file == '' {
		return none
	}
	return CliOptions{
		command:         'run'
		script_file:     file
		script_args:     read_env_script_args(args_file)
		as_module:       os.getenv('VJS_AS_MODULE') == '1'
		runtime_profile: os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	}
}

fn parse_args(args []string) CliOptions {
	if args.len == 0 {
		if opts := parse_env_options() {
			return opts
		}
		return CliOptions{
			command: 'help'
		}
	}

	mut rest := args.clone()
	mut command := 'run'
	if rest[0] in ['--help', '-h', 'help'] {
		return CliOptions{
			command: 'help'
		}
	}
	if rest[0] in ['--version', '-v', 'version'] {
		return CliOptions{
			command: 'version'
		}
	}
	if rest[0] in ['run', 'check', 'check-runtime', 'capabilities', 'host-capabilities', 'install',
		'repair', 'ls', 'list', 'remove', 'uninstall'] {
		command = rest[0]
		rest = rest[1..].clone()
	}

	if command == 'install' || command == 'repair' || command == 'remove' || command == 'uninstall'
		|| command == 'ls' || command == 'list' {
		mut specs := []string{}
		mut registry := os.getenv_opt('VJSX_NPM_REGISTRY') or { 'https://registry.npmjs.org' }
		mut install_dev := false
		mut list_depth := -1
		mut list_omit := []string{}
		mut list_json := false
		mut i := 0
		for i < rest.len {
			arg := rest[i]
			if (command == 'ls' || command == 'list') && arg.starts_with('--depth=') {
				depth_value := arg['--depth='.len..]
				list_depth = depth_value.int()
				if list_depth < 0 {
					fail('depth must be 0 or greater')
				}
				i++
				continue
			}
			if (command == 'ls' || command == 'list') && arg.starts_with('--omit=') {
				append_list_omit(arg['--omit='.len..], mut list_omit)
				i++
				continue
			}
			match arg {
				'--registry' {
					if command != 'install' && command != 'repair' {
						fail('${arg} is only valid for install or repair')
					}
					if i + 1 >= rest.len {
						fail('missing registry URL after ${arg}')
					}
					registry = rest[i + 1]
					i++
				}
				'--dev' {
					if command != 'install' {
						fail('${arg} is only valid for install')
					}
					install_dev = true
				}
				'--depth', '-d' {
					if command != 'ls' && command != 'list' {
						fail('${arg} is only valid for ls')
					}
					if i + 1 >= rest.len {
						fail('missing depth after ${arg}')
					}
					list_depth = rest[i + 1].int()
					if list_depth < 0 {
						fail('depth must be 0 or greater')
					}
					i++
				}
				'--all' {
					if command != 'ls' && command != 'list' {
						fail('${arg} is only valid for ls')
					}
					list_depth = -1
				}
				'--omit' {
					if command != 'ls' && command != 'list' {
						fail('${arg} is only valid for ls')
					}
					if i + 1 >= rest.len {
						fail('missing dependency type after ${arg}')
					}
					append_list_omit(rest[i + 1], mut list_omit)
					i++
				}
				'--production', '--prod' {
					if command != 'ls' && command != 'list' {
						fail('${arg} is only valid for ls')
					}
					append_list_omit('dev', mut list_omit)
				}
				'--json' {
					if command != 'ls' && command != 'list' {
						fail('${arg} is only valid for ls')
					}
					list_json = true
				}
				'--help', '-h' {
					usage()
					exit(0)
				}
				else {
					if arg.starts_with('-') {
						fail('unknown ${command} flag: ${arg}')
					}
					specs << arg
				}
			}
			i++
		}
		return CliOptions{
			command:          command
			install_specs:    specs
			install_registry: registry
			install_dev:      install_dev
			list_depth:       list_depth
			list_omit:        list_omit
			list_json:        list_json
			runtime_profile:  'node'
		}
	}

	if command == 'capabilities' || command == 'host-capabilities' {
		mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { '' }
		mut i := 0
		for i < rest.len {
			arg := rest[i]
			match arg {
				'--runtime', '-r' {
					if i + 1 >= rest.len {
						fail('missing runtime profile after ${arg}')
					}
					runtime_profile = rest[i + 1]
					i++
				}
				'--help', '-h' {
					usage()
					exit(0)
				}
				else {
					if arg.starts_with('-') {
						fail('unknown ${command} flag: ${arg}')
					}
					fail('unexpected ${command} argument: ${arg}')
				}
			}
			i++
		}
		if runtime_profile != '' && runtime_profile !in ['node', 'script', 'browser'] {
			fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
		}
		return CliOptions{
			command:         command
			runtime_profile: runtime_profile
		}
	}

	mut script_file := ''
	mut script_args := []string{}
	mut as_module := false
	mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	mut i := 0
	for i < rest.len {
		arg := rest[i]
		if script_file != '' {
			script_args << arg
			i++
			continue
		}
		match arg {
			'--module', '-m' {
				as_module = true
			}
			'--runtime', '-r' {
				if i + 1 >= rest.len {
					fail('missing runtime profile after ${arg}')
				}
				runtime_profile = rest[i + 1]
				i++
			}
			'--help', '-h' {
				usage()
				exit(0)
			}
			else {
				if arg.starts_with('-') {
					fail('unknown flag: ${arg}')
				}
				script_file = arg
			}
		}
		i++
	}

	if runtime_profile !in ['node', 'script', 'browser'] {
		fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
	}
	if command == 'check-runtime' {
		return CliOptions{
			command:         command
			runtime_profile: runtime_profile
		}
	}
	if runtime_profile == 'browser' && !as_module {
		fail('browser runtime requires module mode\nuse --module with --runtime browser')
	}
	if script_file == '' {
		fail('missing script path')
	}
	as_module = validate_script_type(script_file, as_module)
	return CliOptions{
		command:         command
		script_file:     script_file
		script_args:     script_args
		as_module:       as_module
		runtime_profile: runtime_profile
	}
}

fn append_list_omit(value string, mut list_omit []string) {
	for item in value.split(',') {
		kind := item.trim_space()
		if kind == '' {
			continue
		}
		if kind !in ['dev', 'optional', 'peer'] {
			fail('unsupported omit value: ${kind}')
		}
		if kind !in list_omit {
			list_omit << kind
		}
	}
}

fn install_runtime(ctx &vjsx.Context, runtime_profile string, script_dir string, script_parent string, prev_dir string, process_args []string) {
	match runtime_profile {
		'node' {
			ctx.install_node_runtime(
				fs_roots:     [script_dir, script_parent, prev_dir]
				process_args: process_args
			)
		}
		'script' {
			ctx.install_script_runtime(
				fs_roots:     [script_dir, script_parent, prev_dir]
				process_args: process_args
			)
		}
		'browser' {
			runtimejs.install_cli_browser_runtime(ctx)
		}
		else {
			fail('unknown runtime profile: ${runtime_profile}')
		}
	}
}

fn check_runtime(runtime_profile string) !string {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	wd := os.getwd()
	install_runtime(ctx, runtime_profile, wd, os.dir(wd), wd, ['vjsx', 'check-runtime'])
	value := ctx.eval('typeof globalThis === "object"', vjsx.type_global)!
	defer {
		value.free()
	}
	if !value.to_bool() {
		return error('globalThis is not available')
	}
	if runtime_profile == 'browser' {
		browser_value := ctx.eval('typeof window === "object" && typeof self === "object" && typeof fetch === "function" && typeof EventTarget === "function"',
			vjsx.type_global)!
		defer {
			browser_value.free()
		}
		if !browser_value.to_bool() {
			return error('browser runtime profile is incomplete')
		}
		return 'ok\n'
	}
	kind := match runtime_profile {
		'node' { vjsx.RuntimeProfileKind.node }
		'script' { vjsx.RuntimeProfileKind.script }
		else { vjsx.RuntimeProfileKind.unknown }
	}
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	if !snapshot.matches(kind) {
		missing := snapshot.missing_for(kind)
		return error('runtime profile is incomplete: ${missing.join(', ')}')
	}
	return 'ok\n'
}

fn capability_status(value bool) string {
	if value {
		return 'yes'
	}
	return 'no'
}

fn append_capability(mut lines []string, name string, available bool) {
	lines << '  ${capability_status(available)} ${name}'
}

fn runtime_capabilities(runtime_profile string) !string {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	wd := os.getwd()
	install_runtime(ctx, runtime_profile, wd, os.dir(wd), wd, ['vjsx', 'capabilities'])
	snapshot := vjsx.runtime_profile_snapshot(ctx)
	mut lines := []string{}
	lines << 'runtime: ${runtime_profile}'
	lines << 'globals:'
	append_capability(mut lines, 'globalThis', runtime_profile_has_expr(ctx,
		'typeof globalThis === "object"'))
	append_capability(mut lines, 'AbortController', snapshot.has_abort_controller)
	append_capability(mut lines, 'AbortSignal', snapshot.has_abort_signal)
	append_capability(mut lines, 'EventTarget', snapshot.has_event_target)
	append_capability(mut lines, 'URL', snapshot.has_url)
	append_capability(mut lines, 'Buffer', snapshot.has_buffer)
	append_capability(mut lines, 'process', snapshot.has_process)
	append_capability(mut lines, 'setTimeout', snapshot.has_set_timeout)
	append_capability(mut lines, 'clearTimeout', snapshot.has_clear_timeout)
	append_capability(mut lines, 'fetch', snapshot.has_fetch)
	append_capability(mut lines, 'window', runtime_profile_has_expr(ctx,
		'typeof window === "object"'))
	append_capability(mut lines, 'self', runtime_profile_has_expr(ctx, 'typeof self === "object"'))
	append_capability(mut lines, 'Blob',
		runtime_profile_has_expr(ctx, 'typeof Blob === "function"'))
	append_capability(mut lines, 'FormData', runtime_profile_has_expr(ctx,
		'typeof FormData === "function"'))
	append_capability(mut lines, 'ReadableStream', runtime_profile_has_expr(ctx,
		'typeof ReadableStream === "function"'))
	append_capability(mut lines, 'TextEncoder', runtime_profile_has_expr(ctx,
		'typeof TextEncoder === "function"'))
	append_capability(mut lines, 'Intl', runtime_profile_has_expr(ctx, 'typeof Intl === "object"'))
	append_capability(mut lines, 'crypto.subtle', runtime_profile_has_expr(ctx,
		'typeof crypto === "object" && typeof crypto.subtle === "object"'))
	lines << 'modules:'
	append_capability(mut lines, 'node:timers/promises', snapshot.has_node_timers_promises)
	append_capability(mut lines, 'fs', snapshot.has_fs_module)
	append_capability(mut lines, 'path', snapshot.has_path_module)
	append_capability(mut lines, 'http', snapshot.has_http_module)
	append_capability(mut lines, 'https', snapshot.has_https_module)
	append_capability(mut lines, 'os', snapshot.has_os_module)
	append_capability(mut lines, 'child_process', snapshot.has_child_process_module)
	append_capability(mut lines, 'sqlite', snapshot.has_sqlite_module)
	append_capability(mut lines, 'mysql', snapshot.has_mysql_module)
	return lines.join('\n') + '\n'
}

fn runtime_profile_has_expr(ctx &vjsx.Context, expr string) bool {
	value := ctx.eval(expr, vjsx.type_global) or { return false }
	defer {
		value.free()
	}
	return value.to_bool()
}

fn capabilities_text(runtime_profile string) !string {
	if runtime_profile != '' {
		return runtime_capabilities(runtime_profile)
	}
	mut output := 'Supported host runtime profiles:\n\n'
	for profile in ['node', 'script', 'browser'] {
		output += runtime_capabilities(profile)! + '\n'
	}
	return output
}

fn run_script(opts CliOptions) !string {
	script_path := os.real_path(opts.script_file)
	if !os.exists(script_path) {
		fail('script not found: ${script_path}')
	}

	script_dir := os.dir(script_path)
	script_parent := os.dir(script_dir)
	mut process_args := [script_path]
	process_args << opts.script_args

	prev_dir := os.getwd()
	os.chdir(script_dir) or { fail(err.msg()) }
	defer {
		os.chdir(prev_dir) or {}
	}

	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()

	install_runtime(ctx, opts.runtime_profile, script_dir, script_parent, prev_dir, process_args)

	value := runtimejs.run_runtime_entry(ctx, script_path, opts.as_module,
		script_path + '.vjsbuild') or { fail(err.msg()) }
	defer {
		value.free()
	}

	if !value.is_undefined() {
		return value.to_string()
	}
	return ''
}

fn main() {
	if cli_cwd := os.getenv_opt('VJS_CLI_CWD') {
		if cli_cwd != '' {
			os.chdir(cli_cwd) or { fail(err.msg()) }
		}
	}
	opts := parse_args(os.args[1..])
	output := match opts.command {
		'help' {
			help_text()
		}
		'version' {
			version_text()
		}
		'check-runtime' {
			check_runtime(opts.runtime_profile) or { fail(err.msg()) }
		}
		'capabilities', 'host-capabilities' {
			capabilities_text(opts.runtime_profile) or { fail(err.msg()) }
		}
		'check' {
			run_script(opts) or { fail(err.msg()) }
		}
		'install' {
			install_packages(opts) or { fail(err.msg()) }
		}
		'ls', 'list' {
			list_packages(opts) or { fail(err.msg()) }
		}
		'remove', 'uninstall' {
			remove_packages(opts) or { fail(err.msg()) }
		}
		'repair' {
			repair_packages(opts) or { fail(err.msg()) }
		}
		else {
			run_script(opts) or { fail(err.msg()) }
		}
	}
	if output != '' {
		print(output)
	}
}

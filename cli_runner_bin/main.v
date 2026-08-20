module main

import os
import vjsx
import runtimejs

const cli_version = vjsx.version

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
	output_file      string
	entry_only       bool
	bundle           bool
	runner_file      string
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
  vjsx compile --entry-only [--runtime|-r <node|script|browser>] <input.js> -o <output.qbc>
  vjsx compile --bundle [--runtime|-r <node|script|browser>] <entry.js> -o <app.vjsx>
  vjsx build [--runtime|-r <node|script|browser>] [--runner <path>] <entry.js> -o <app>
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
  -h, --help            Show this help text
  -v, --version         Show the vjsx version
  -m, --module          Run or check input as an ES module
  -r, --runtime <name>  Select host runtime profile: node, script, browser

Runtime commands:
  run           Execute a JavaScript or TypeScript file (default command).
  check         Load and execute a file, returning a non-zero status on failure.
  check-runtime Verify that the selected runtime profile is complete.
  capabilities Print globals, modules, and host features exposed by a profile.

Compile command:
  compile       Compile a file or static project graph to QuickJS bytecode.
  build         Package a project bundle with the native vjsx app runner.

Compile options:
  --entry-only          Compile one self-contained file;
                        imports and require() dependencies are not bundled.
  --bundle              Compile the statically reachable JS/TS/CommonJS/JSON graph
                        into one self-contained .vjsx application bundle.
  -o, --output <file>   Write a .qbc entry artifact or .vjsx project bundle.
  -r, --runtime <name>  Record the required runtime profile in the artifact.

Build options:
  --runner <path>       Use this unbundled vjsx-app-runner executable. By default,
                        use the runner installed next to the vjsx executable.
  -o, --output <file>   Write the single-file native application executable.

Bytecode artifacts:
  Loading preserves module.exports, so embedded hosts can access exports such as
  Parser through ctx.load_bytecode(bytecode). Artifacts are tied to the vjsx and
  QuickJS ABI and to the selected runtime profile. Load only trusted bytecode.

Project bundles:
  A .vjsx bundle contains its entry manifest and all statically reachable module
  bytecode. Running it does not read project source files or node_modules.

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

Examples:
  vjsx app.js arg1 arg2
  vjsx --module --runtime node app.mjs
  vjsx check --module app.mjs
  vjsx compile --entry-only --runtime node parser.umd.js -o parser.qbc
  vjsx compile --bundle --runtime node src/main.ts -o myapp.vjsx
  vjsx run myapp.vjsx
  vjsx build --runtime node src/main.ts -o myapp
  vjsx capabilities --runtime browser
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
	if script_file.ends_with('.vjsx') {
		return false
	}
	if script_file.ends_with('.mjs') || script_file.ends_with('.mts') {
		enable_module = true
		return enable_module
	}
	if script_file.ends_with('.js') || script_file.ends_with('.cjs') || script_file.ends_with('.ts')
		|| script_file.ends_with('.cts') {
		return enable_module
	}
	fail('unsupported script type: ${script_file}\nexpected a .js, .mjs, .cjs, .ts, .mts, .cts, or .vjsx file')
}

fn parse_env_options() ?CliOptions {
	file := os.getenv('VJS_SCRIPT_FILE')
	args_file := os.getenv('VJS_ARGS_FILE')
	if file == '' {
		return none
	}
	runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
	if runtime_profile !in ['node', 'script', 'browser'] {
		fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
	}
	as_module := os.getenv('VJS_AS_MODULE') == '1'
	if runtime_profile == 'browser' && !as_module {
		fail('browser runtime requires module mode\nuse --module with --runtime browser')
	}
	return CliOptions{
		command:         'run'
		script_file:     file
		script_args:     read_env_script_args(args_file)
		as_module:       validate_script_type(file, as_module)
		runtime_profile: runtime_profile
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
		'repair', 'ls', 'list', 'remove', 'uninstall', 'compile', 'build'] {
		command = rest[0]
		rest = rest[1..].clone()
	}

	if command == 'compile' {
		mut input_file := ''
		mut output_file := ''
		mut entry_only := false
		mut bundle := false
		mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
		mut i := 0
		for i < rest.len {
			arg := rest[i]
			match arg {
				'--entry-only' {
					entry_only = true
				}
				'--bundle' {
					bundle = true
				}
				'--runtime', '-r' {
					if i + 1 >= rest.len {
						fail('missing runtime profile after ${arg}')
					}
					runtime_profile = rest[i + 1]
					i++
				}
				'--output', '-o' {
					if i + 1 >= rest.len {
						fail('missing output path after ${arg}')
					}
					output_file = rest[i + 1]
					i++
				}
				'--help', '-h' {
					usage()
					exit(0)
				}
				else {
					if arg.starts_with('-') {
						fail('unknown compile flag: ${arg}')
					}
					if input_file != '' {
						fail('unexpected compile argument: ${arg}')
					}
					input_file = arg
				}
			}
			i++
		}
		if entry_only == bundle {
			fail('vjsx compile requires exactly one of --entry-only or --bundle')
		}
		if runtime_profile !in ['node', 'script', 'browser'] {
			fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
		}
		if input_file == '' {
			fail('missing compile input path')
		}
		if output_file == '' {
			fail('missing compile output path; use -o <output.qbc|app.vjsx>')
		}
		if bundle && !output_file.ends_with('.vjsx') {
			fail('bundle output must use the .vjsx extension')
		}
		return CliOptions{
			command:         command
			script_file:     input_file
			output_file:     output_file
			entry_only:      entry_only
			bundle:          bundle
			runtime_profile: runtime_profile
		}
	}

	if command == 'build' {
		mut input_file := ''
		mut output_file := ''
		mut runner_file := ''
		mut runtime_profile := os.getenv_opt('VJS_RUNTIME_PROFILE') or { 'node' }
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
				'--output', '-o' {
					if i + 1 >= rest.len {
						fail('missing output path after ${arg}')
					}
					output_file = rest[i + 1]
					i++
				}
				'--runner' {
					if i + 1 >= rest.len {
						fail('missing app runner path after ${arg}')
					}
					runner_file = rest[i + 1]
					i++
				}
				'--help', '-h' {
					usage()
					exit(0)
				}
				else {
					if arg.starts_with('-') {
						fail('unknown build flag: ${arg}')
					}
					if input_file != '' {
						fail('unexpected build argument: ${arg}')
					}
					input_file = arg
				}
			}
			i++
		}
		if runtime_profile !in ['node', 'script', 'browser'] {
			fail('unknown runtime profile: ${runtime_profile}\nexpected one of: node, script, browser')
		}
		if input_file == '' {
			fail('missing build input path')
		}
		if output_file == '' {
			fail('missing build output path; use -o <app>')
		}
		return CliOptions{
			command:         command
			script_file:     input_file
			output_file:     output_file
			runner_file:     runner_file
			runtime_profile: runtime_profile
		}
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
	if runtime_profile == 'browser' && !as_module && !script_file.ends_with('.vjsx') {
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
	if script_path.ends_with('.vjsx') {
		bundle := os.read_bytes(script_path)!
		mut app := ctx.load_bundle(bundle)!
		defer {
			app.close()
		}
		ctx.end()
		return ''
	}

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

fn compile_script(opts CliOptions) !string {
	input_path := os.real_path(opts.script_file)
	if !os.exists(input_path) {
		return error('script not found: ${input_path}')
	}
	output_path := if os.is_abs_path(opts.output_file) {
		opts.output_file
	} else {
		os.join_path(os.getwd(), opts.output_file)
	}
	output_dir := os.dir(output_path)
	if output_dir != '' && output_dir != '.' {
		os.mkdir_all(output_dir)!
	}
	if opts.bundle {
		mut compiler := vjsx.new_runtime_session()
		defer {
			compiler.close()
		}
		app_name := os.file_name(output_path).all_before_last('.')
		bundle := runtimejs.compile_project_bundle(compiler.context(), input_path,
			app_name:        app_name
			runtime_profile: opts.runtime_profile
		)!
		os.write_file_array(output_path, bundle)!
	} else {
		source := os.read_file(input_path)!
		bytecode := vjsx.compile_module(source,
			filename:        input_path
			runtime_profile: opts.runtime_profile
		)!
		os.write_file_array(output_path, bytecode)!
	}
	return ''
}

fn default_app_runner_path() string {
	runner_name := $if windows { 'vjsx-app-runner.exe' } $else { 'vjsx-app-runner' }
	return os.join_path(os.dir(os.real_path(os.executable())), runner_name)
}

fn resolve_app_runner(opts CliOptions) !string {
	candidate := if opts.runner_file != '' {
		opts.runner_file
	} else if configured := os.getenv_opt('VJS_APP_RUNNER') {
		configured
	} else {
		default_app_runner_path()
	}
	resolved := os.real_path(candidate)
	if !os.is_file(resolved) {
		return error('vjsx app runner not found: ${resolved}\ninstall vjsx-app-runner next to vjsx or pass --runner <path>')
	}
	return resolved
}

fn build_app(opts CliOptions) !string {
	input_path := os.real_path(opts.script_file)
	if !os.is_file(input_path) {
		return error('script not found: ${input_path}')
	}
	output_path := if os.is_abs_path(opts.output_file) {
		opts.output_file
	} else {
		os.join_path(os.getwd(), opts.output_file)
	}
	runner_path := resolve_app_runner(opts)!
	mut compiler := vjsx.new_runtime_session()
	defer {
		compiler.close()
	}
	app_name := os.file_name(output_path).all_before_last('.')
	bundle := runtimejs.compile_project_bundle(compiler.context(), input_path,
		app_name:        app_name
		runtime_profile: opts.runtime_profile
	)!
	vjsx.pack_app_executable(runner_path, bundle, output_path)!
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
		'compile' {
			compile_script(opts) or { fail(err.msg()) }
		}
		'build' {
			build_app(opts) or { fail(err.msg()) }
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

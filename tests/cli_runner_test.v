import os
import vjs

struct ModuleRewrite {
	from     string
	to       string
	resolved string
}

fn append_output(path string, text string) {
	prev := if os.exists(path) { os.read_file(path) or { '' } } else { '' }
	os.write_file(path, prev + text) or { panic(err) }
}

fn is_typescript_file(path string) bool {
	return path.ends_with('.ts') || path.ends_with('.mts') || path.ends_with('.cts')
}

fn is_javascript_file(path string) bool {
	return path.ends_with('.js') || path.ends_with('.mjs') || path.ends_with('.cjs')
}

fn is_local_module_specifier(specifier string) bool {
	return specifier.starts_with('./') || specifier.starts_with('../')
}

fn typescript_runtime_path() string {
	return os.join_path(@VMODROOT, 'thirdparty', 'typescript', 'lib', 'typescript.js')
}

fn install_typescript_host_bridge(ctx &vjs.Context) {
	global := ctx.js_global()
	host := ctx.js_object()
	host.set('readFile', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_undefined()
		}
		path := args[0].str()
		if !os.exists(path) || os.is_dir(path) {
			return ctx.js_undefined()
		}
		return ctx.js_string(os.read_file(path) or { return ctx.js_undefined() })
	}))
	host.set('fileExists', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		path := args[0].str()
		return ctx.js_bool(os.exists(path) && !os.is_dir(path))
	}))
	host.set('directoryExists', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(os.is_dir(args[0].str()))
	}))
	host.set('getDirectories', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_array()
		}
		path := args[0].str()
		mut arr := ctx.js_array()
		if os.is_dir(path) {
			entries := os.ls(path) or { []string{} }
			mut index := 0
			for entry in entries {
				full := os.join_path(path, entry)
				if os.is_dir(full) {
					arr.set(index, full)
					index++
				}
			}
		}
		return arr
	}))
	host.set('readDirectory', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_array()
		}
		root := args[0].str()
		mut arr := ctx.js_array()
		if !os.is_dir(root) {
			return arr
		}
		mut stack := [root]
		mut index := 0
		for stack.len > 0 {
			current := stack.pop()
			entries := os.ls(current) or { continue }
			for entry in entries {
				full := os.join_path(current, entry)
				if os.is_dir(full) {
					stack << full
				} else {
					arr.set(index, full)
					index++
				}
			}
		}
		return arr
	}))
	host.set('realpath', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		if args.len == 0 {
			return ctx.js_string('')
		}
		path := args[0].str()
		if !os.exists(path) {
			return ctx.js_string(path)
		}
		return ctx.js_string(os.real_path(path))
	}))
	host.set('getCurrentDirectory', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		return ctx.js_string(os.getwd())
	}))
	host.set('useCaseSensitiveFileNames', ctx.js_function(fn [ctx] (args []vjs.Value) vjs.Value {
		$if windows {
			return ctx.js_bool(false)
		}
		return ctx.js_bool(true)
	}))
	global.set('__vjs_host', host)
	host.free()
	global.free()
}

fn install_typescript_transpiler(ctx &vjs.Context) ! {
	ts_path := typescript_runtime_path()
	if !os.exists(ts_path) {
		return error('TypeScript runtime not found: ${ts_path}')
	}
	install_typescript_host_bridge(ctx)
	ctx.run_file(ts_path) or { return error('failed to load TypeScript runtime: ${err.msg()}') }
	ctx.run(
		'globalThis.__vjs_format_diagnostics = function(diagnostics) {
			return (diagnostics || [])
				.filter((entry) => entry.category === ts.DiagnosticCategory.Error)
				.map((entry) => {
					const message = ts.flattenDiagnosticMessageText(entry.messageText, "\\n");
					if (!entry.file) {
						return message;
					}
					const point = entry.file.getLineAndCharacterOfPosition(entry.start || 0);
					return entry.file.fileName + ":" + String(point.line + 1) + ":" + String(point.character + 1) + " " + message;
				});
		};
		globalThis.__vjs_normalize_tsconfig = function(configText, fileName) {
			if (!configText) {
				return JSON.stringify({ compilerOptions: {}, configDir: "" });
			}
			const configDir = fileName.replace(/[\\\\/][^\\\\/]+$/, "");
			const host = {
				useCaseSensitiveFileNames: !!__vjs_host.useCaseSensitiveFileNames(),
				fileExists: (path) => !!__vjs_host.fileExists(path),
				readFile: (path) => __vjs_host.readFile(path),
				readDirectory: (path, extensions, exclude, include, depth) => __vjs_host.readDirectory(path),
				onUnRecoverableConfigFileDiagnostic: (diagnostic) => {
					throw new Error(globalThis.__vjs_format_diagnostics([diagnostic]).join("\\n"));
				}
			};
			const parsed = ts.parseJsonText(fileName, configText);
			const result = ts.parseJsonSourceFileConfigFileContent(parsed, host, configDir, undefined, fileName);
			const diagnostics = globalThis.__vjs_format_diagnostics(result.errors || []);
			if (diagnostics.length > 0) {
				throw new Error(diagnostics.join("\\n"));
			}
			return JSON.stringify({
				compilerOptions: result.options || {},
				configDir
			});
		};
		globalThis.__vjs_transpile_typescript = function(input, fileName, asModule, configText) {
			const config = configText ? JSON.parse(configText) : { compilerOptions: {} };
			const compilerOptions = Object.assign({}, config.compilerOptions || {});
			if (compilerOptions.target == null) compilerOptions.target = ts.ScriptTarget.ESNext;
			if (compilerOptions.module == null) compilerOptions.module = asModule ? ts.ModuleKind.ESNext : ts.ModuleKind.None;
			compilerOptions.sourceMap = false;
			compilerOptions.inlineSourceMap = false;
			compilerOptions.inlineSources = false;
			const result = ts.transpileModule(input, {
				fileName,
				reportDiagnostics: true,
				compilerOptions
			});
			const diagnostics = globalThis.__vjs_format_diagnostics(result.diagnostics || []);
			if (diagnostics.length > 0) {
				throw new Error(diagnostics.join("\\n"));
			}
			return result.outputText;
		};'
	) or { return error('failed to install TypeScript transpiler: ${err.msg()}') }
	ctx.run(
		'globalThis.__vjs_list_module_imports = function(input, fileName) {
			const info = ts.preProcessFile(input, true, true);
			return (info.importedFiles || []).map((entry) => entry.fileName).join("\\n");
		};'
	) or { return error('failed to install TypeScript import scanner: ${err.msg()}') }
	ctx.run(
		'globalThis.__vjs_resolve_ts_module = function(specifier, importerFileName, configText) {
			const config = configText ? JSON.parse(configText) : { compilerOptions: {}, configDir: "" };
			const compilerOptions = Object.assign({}, config.compilerOptions || {});
			const host = {
				fileExists: (path) => !!__vjs_host.fileExists(path),
				readFile: (path) => __vjs_host.readFile(path),
				directoryExists: (path) => !!__vjs_host.directoryExists(path),
				getDirectories: (path) => __vjs_host.getDirectories(path),
				realpath: (path) => __vjs_host.realpath(path),
				getCurrentDirectory: () => config.configDir || __vjs_host.getCurrentDirectory(),
				useCaseSensitiveFileNames: () => !!__vjs_host.useCaseSensitiveFileNames(),
				getCanonicalFileName: (fileName) => __vjs_host.useCaseSensitiveFileNames() ? fileName : fileName.toLowerCase(),
				getNewLine: () => "\\n"
			};
			const result = ts.resolveModuleName(specifier, importerFileName, compilerOptions, host);
			return result.resolvedModule ? result.resolvedModule.resolvedFileName : "";
		};
		globalThis.__vjs_pick_package_target = function(target) {
			if (typeof target === "string") return target;
			if (!target || typeof target !== "object" || Array.isArray(target)) return "";
			if (typeof target.import === "string") return target.import;
			if (typeof target.default === "string") return target.default;
			if (typeof target.module === "string") return target.module;
			if (typeof target.browser === "string") return target.browser;
			for (const key of Object.keys(target)) {
				const nested = globalThis.__vjs_pick_package_target(target[key]);
				if (nested) return nested;
			}
			return "";
		};
		globalThis.__vjs_package_entry = function(packageText, subpath) {
			if (!packageText) {
				return "";
			}
			const pkg = JSON.parse(packageText);
			const key = subpath ? "./" + subpath : ".";
			if (pkg.exports) {
				if (typeof pkg.exports === "string" && key === ".") return pkg.exports;
				if (typeof pkg.exports === "object" && !Array.isArray(pkg.exports)) {
					if (!Object.keys(pkg.exports).some((entry) => entry.startsWith(".")) && key === ".") {
						const direct = globalThis.__vjs_pick_package_target(pkg.exports);
						if (direct) return direct;
					}
					if (key in pkg.exports) {
						const mapped = globalThis.__vjs_pick_package_target(pkg.exports[key]);
						if (mapped) return mapped;
					}
				}
			}
			if (key == "." && typeof pkg.module === "string") return pkg.module;
			if (key == "." && typeof pkg.main === "string") return pkg.main;
			return "";
		};'
	) or { return error('failed to install TypeScript resolver helpers: ${err.msg()}') }
}

fn normalize_tsconfig(ctx &vjs.Context, config_path string, config_text string) !string {
	normalize_fn := ctx.js_global('__vjs_normalize_tsconfig')
	defer {
		normalize_fn.free()
	}
	if normalize_fn.is_undefined() {
		return error('TypeScript config parser is not installed')
	}
	output := ctx.call(normalize_fn, config_text, config_path)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn transpile_typescript(ctx &vjs.Context, script_path string, as_module bool, config_json string) !string {
	source := os.read_file(script_path)!
	transpile_fn := ctx.js_global('__vjs_transpile_typescript')
	defer {
		transpile_fn.free()
	}
	if transpile_fn.is_undefined() {
		return error('TypeScript transpiler is not installed')
	}
	output := ctx.call(transpile_fn, source, script_path, as_module, config_json)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn list_module_imports(ctx &vjs.Context, script_path string) ![]string {
	source := os.read_file(script_path)!
	list_fn := ctx.js_global('__vjs_list_module_imports')
	defer {
		list_fn.free()
	}
	if list_fn.is_undefined() {
		return error('TypeScript import scanner is not installed')
	}
	output := ctx.call(list_fn, source, script_path)!
	defer {
		output.free()
	}
	return output.to_string().split('\n').filter(it.len > 0)
}

fn resolve_ts_module(ctx &vjs.Context, importer_path string, specifier string, config_json string) !string {
	resolve_fn := ctx.js_global('__vjs_resolve_ts_module')
	defer {
		resolve_fn.free()
	}
	if resolve_fn.is_undefined() {
		return error('TypeScript resolver is not installed')
	}
	output := ctx.call(resolve_fn, specifier, importer_path, config_json)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn package_entry(ctx &vjs.Context, package_json_path string, subpath string) !string {
	text := os.read_file(package_json_path)!
	entry_fn := ctx.js_global('__vjs_package_entry')
	defer {
		entry_fn.free()
	}
	if entry_fn.is_undefined() {
		return error('package entry helper is not installed')
	}
	output := ctx.call(entry_fn, text, subpath)!
	defer {
		output.free()
	}
	return output.to_string()
}

fn run_transpiled_source(ctx &vjs.Context, source string, script_name string, flag int) !vjs.Value {
	value := ctx.js_eval(source, script_name, flag)!
	ctx.end()
	return value
}

fn relative_path(from string, to string) string {
	from_abs := os.abs_path(from)
	to_abs := os.abs_path(to)
	sep := os.path_separator.str()
	from_parts := from_abs.split(sep).filter(it.len > 0)
	to_parts := to_abs.split(sep).filter(it.len > 0)
	mut common := 0
	for common < from_parts.len && common < to_parts.len && from_parts[common] == to_parts[common] {
		common++
	}
	mut parts := []string{}
	for _ in common .. from_parts.len {
		parts << '..'
	}
	for part in to_parts[common..] {
		parts << part
	}
	if parts.len == 0 {
		return '.'
	}
	return parts.join(sep)
}

fn mirrored_runtime_path(root string, source_path string) string {
	normalized := source_path.replace('\\', '/')
	trimmed := if normalized.starts_with('/') { normalized[1..] } else { normalized }
	return os.join_path(root, trimmed)
}

fn file_relative_specifier(from_path string, to_path string) string {
	mut rel := relative_path(os.dir(from_path), to_path)
	if !rel.starts_with('.') {
		rel = './' + rel
	}
	return rel.replace('\\', '/')
}

fn resolve_local_module(importer_path string, specifier string) !string {
	base := os.join_path(os.dir(importer_path), specifier)
	candidates := [
		base,
		base + '.ts',
		base + '.mts',
		base + '.cts',
		base + '.js',
		base + '.mjs',
		base + '.cjs',
		os.join_path(base, 'index.ts'),
		os.join_path(base, 'index.mts'),
		os.join_path(base, 'index.cts'),
		os.join_path(base, 'index.js'),
		os.join_path(base, 'index.mjs'),
		os.join_path(base, 'index.cjs'),
	]
	for candidate in candidates {
		if os.exists(candidate) && !os.is_dir(candidate) {
			return os.real_path(candidate)
		}
	}
	return error('cannot resolve local module "${specifier}" from ${importer_path}')
}

fn find_tsconfig_path(start_dir string) string {
	mut current := os.real_path(start_dir)
	for {
		candidate := os.join_path(current, 'tsconfig.json')
		if os.exists(candidate) && !os.is_dir(candidate) {
			return candidate
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return ''
}

fn load_typescript_config(ctx &vjs.Context, script_path string) !string {
	config_path := find_tsconfig_path(os.dir(script_path))
	if config_path == '' {
		return ''
	}
	return normalize_tsconfig(ctx, config_path, os.read_file(config_path)!)
}

fn resolve_node_module(ctx &vjs.Context, importer_path string, specifier string) !string {
	mut package_name := specifier
	mut package_subpath := ''
	parts := specifier.split('/')
	if specifier.starts_with('@') {
		if parts.len < 2 {
			return error('invalid scoped package: ${specifier}')
		}
		package_name = parts[..2].join('/')
		if parts.len > 2 {
			package_subpath = parts[2..].join('/')
		}
	} else if parts.len > 1 {
		package_name = parts[0]
		package_subpath = parts[1..].join('/')
	}
	mut current := os.dir(importer_path)
	for {
		package_root := os.join_path(current, 'node_modules', package_name)
		if os.is_dir(package_root) {
			package_json_path := os.join_path(package_root, 'package.json')
			if os.exists(package_json_path) {
				entry := package_entry(ctx, package_json_path, package_subpath) or { '' }
				if entry != '' {
					resolved := resolve_local_module(os.join_path(package_root, '_entry.js'), './' + entry) or { '' }
					if resolved != '' {
						return resolved
					}
				}
			}
			if package_subpath != '' {
				return resolve_local_module(os.join_path(package_root, '_entry.js'), './' + package_subpath)
			}
			return resolve_local_module(os.join_path(package_root, '_entry.js'), './index')
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return error('cannot resolve package "${specifier}" from ${importer_path}')
}

fn resolve_module_specifier(ctx &vjs.Context, importer_path string, specifier string, config_json string) !string {
	if is_local_module_specifier(specifier) {
		return resolve_local_module(importer_path, specifier)
	}
	resolved := resolve_ts_module(ctx, importer_path, specifier, config_json) or { '' }
	if resolved != '' && !resolved.ends_with('.d.ts') {
		return os.real_path(resolved)
	}
	return resolve_node_module(ctx, importer_path, specifier)
}

fn rewrite_module_specifiers(input string, rewrites []ModuleRewrite) string {
	mut output := input
	for rewrite in rewrites {
		output = output.replace('"${rewrite.from}"', '"${rewrite.to}"')
		output = output.replace('\'${rewrite.from}\'', '\'${rewrite.to}\'')
	}
	return output
}

fn emit_runtime_module_graph(ctx &vjs.Context, source_path string, root string, config_json string, mut seen map[string]bool) ! {
	if source_path in seen {
		return
	}
	seen[source_path] = true
	target_path := mirrored_runtime_path(root, source_path)
	os.mkdir_all(os.dir(target_path))!
	mut rewrites := []ModuleRewrite{}
	for specifier in list_module_imports(ctx, source_path)! {
		resolved := resolve_module_specifier(ctx, source_path, specifier, config_json) or { '' }
		if resolved == '' {
			continue
		}
		if !is_typescript_file(resolved) && !is_javascript_file(resolved) {
			continue
		}
		emit_runtime_module_graph(ctx, resolved, root, config_json, mut seen)!
		rewrites << ModuleRewrite{
			from: specifier
			to: file_relative_specifier(target_path, mirrored_runtime_path(root, resolved))
			resolved: resolved
		}
	}
	if is_typescript_file(source_path) {
		transpiled := transpile_typescript(ctx, source_path, true, config_json)!
		os.write_file(target_path, rewrite_module_specifiers(transpiled, rewrites))!
	} else {
		source := os.read_file(source_path)!
		os.write_file(target_path, rewrite_module_specifiers(source, rewrites))!
	}
}

fn build_typescript_runtime_entry(ctx &vjs.Context, script_path string, as_module bool, out_file string) !string {
	config_json := load_typescript_config(ctx, script_path) or { '' }
	if !as_module {
		return transpile_typescript(ctx, script_path, false, config_json)!
	}
	temp_root := out_file + '.tsbuild'
	os.rmdir_all(temp_root) or {}
	os.mkdir_all(temp_root)!
	mut seen := map[string]bool{}
	emit_runtime_module_graph(ctx, script_path, temp_root, config_json, mut seen)!
	return mirrored_runtime_path(temp_root, script_path)
}

fn test_cli_runner() {
	if os.getenv('VJS_CLI_RUN') != '1' {
		assert true
		return
	}

	file := os.getenv('VJS_SCRIPT_FILE')
	as_module := os.getenv('VJS_AS_MODULE') == '1'
	args_file := os.getenv('VJS_ARGS_FILE')
	out_file := os.getenv('VJS_OUTPUT_FILE')
	assert file != ''
	assert args_file != ''
	assert out_file != ''
	os.write_file(out_file, '') or { panic(err) }

	script_path := os.real_path(file)
	assert os.exists(script_path)

	script_dir := os.dir(script_path)
	script_parent := os.dir(script_dir)
	script_name := os.file_name(script_path)
	script_args := if os.exists(args_file) { os.read_lines(args_file) or { panic(err) } } else { []string{} }
	mut process_args := [script_path]
	process_args << script_args
	prev_dir := os.getwd()
	os.chdir(script_dir) or { panic(err) }
	defer {
		os.chdir(prev_dir) or {}
	}

	rt := vjs.new_runtime()
	defer {
		rt.free()
	}

	ctx := rt.new_context()
	defer {
		ctx.free()
	}

	ctx.install_host(
		fs_roots: [script_dir, script_parent, prev_dir]
		process_args: process_args
		log_fn: fn [out_file] (line string) {
			append_output(out_file, line + '\n')
		}
		error_fn: fn [out_file] (line string) {
			append_output(out_file, line + '\n')
		}
	)

	flag := if as_module { vjs.type_module } else { vjs.type_global }
	if is_typescript_file(script_name) {
		install_typescript_transpiler(ctx) or { panic(err) }
		if as_module {
			temp_entry := build_typescript_runtime_entry(ctx, script_path, true, out_file) or { panic(err) }
			defer {
				os.rmdir_all(out_file + '.tsbuild') or {}
			}
			value := ctx.run_file(temp_entry, flag) or { panic(err) }
			defer {
				value.free()
			}
			if !value.is_undefined() {
				append_output(out_file, value.to_string())
			}
		} else {
			transpiled := build_typescript_runtime_entry(ctx, script_path, false, out_file) or { panic(err) }
			value := run_transpiled_source(ctx, transpiled, script_name, flag) or { panic(err) }
			defer {
				value.free()
			}
			if !value.is_undefined() {
				append_output(out_file, value.to_string())
			}
		}
		return
	}
	value := ctx.run_file(script_name, flag) or { panic(err) }
	defer {
		value.free()
	}

	if !value.is_undefined() {
		append_output(out_file, value.to_string())
	}
}

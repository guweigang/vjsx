import os
import vjs

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

fn install_typescript_transpiler(ctx &vjs.Context) ! {
	ts_path := typescript_runtime_path()
	if !os.exists(ts_path) {
		return error('TypeScript runtime not found: ${ts_path}')
	}
	ctx.run_file(ts_path) or { return error('failed to load TypeScript runtime: ${err.msg()}') }
	ctx.run(
		'globalThis.__vjs_transpile_typescript = function(input, fileName, asModule) {
			const result = ts.transpileModule(input, {
				fileName,
				reportDiagnostics: true,
				compilerOptions: {
					target: ts.ScriptTarget.ESNext,
					module: asModule ? ts.ModuleKind.ESNext : ts.ModuleKind.None,
					sourceMap: false,
					inlineSourceMap: false,
					inlineSources: false
				}
			});
			const diagnostics = (result.diagnostics || [])
				.filter((entry) => entry.category === ts.DiagnosticCategory.Error)
				.map((entry) => {
					const message = ts.flattenDiagnosticMessageText(entry.messageText, "\\n");
					if (!entry.file) {
						return message;
					}
					const point = entry.file.getLineAndCharacterOfPosition(entry.start || 0);
					return entry.file.fileName + ":" + String(point.line + 1) + ":" + String(point.character + 1) + " " + message;
				});
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
}

fn transpile_typescript(ctx &vjs.Context, script_path string, as_module bool) !string {
	source := os.read_file(script_path)!
	transpile_fn := ctx.js_global('__vjs_transpile_typescript')
	defer {
		transpile_fn.free()
	}
	if transpile_fn.is_undefined() {
		return error('TypeScript transpiler is not installed')
	}
	output := ctx.call(transpile_fn, source, script_path, as_module)!
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

fn run_transpiled_source(ctx &vjs.Context, source string, script_name string, flag int) !vjs.Value {
	value := ctx.js_eval(source, script_name, flag)!
	ctx.end()
	return value
}

fn mirrored_runtime_path(root string, source_path string) string {
	normalized := source_path.replace('\\', '/')
	trimmed := if normalized.starts_with('/') { normalized[1..] } else { normalized }
	return os.join_path(root, trimmed)
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

fn emit_runtime_module_graph(ctx &vjs.Context, source_path string, root string, mut seen map[string]bool) ! {
	if source_path in seen {
		return
	}
	seen[source_path] = true
	target_path := mirrored_runtime_path(root, source_path)
	os.mkdir_all(os.dir(target_path))!
	if is_typescript_file(source_path) {
		transpiled := transpile_typescript(ctx, source_path, true)!
		os.write_file(target_path, transpiled)!
	} else {
		os.cp(source_path, target_path)!
	}
	for specifier in list_module_imports(ctx, source_path)! {
		if !is_local_module_specifier(specifier) {
			continue
		}
		resolved := resolve_local_module(source_path, specifier)!
		if is_typescript_file(resolved) || is_javascript_file(resolved) {
			emit_runtime_module_graph(ctx, resolved, root, mut seen)!
		}
	}
}

fn build_typescript_runtime_entry(ctx &vjs.Context, script_path string, as_module bool, out_file string) !string {
	if !as_module {
		return transpile_typescript(ctx, script_path, false)!
	}
	temp_root := out_file + '.tsbuild'
	os.rmdir_all(temp_root) or {}
	os.mkdir_all(temp_root)!
	mut seen := map[string]bool{}
	emit_runtime_module_graph(ctx, script_path, temp_root, mut seen)!
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

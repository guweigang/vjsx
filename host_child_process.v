module vjsx

import os

enum ChildProcessStdioMode {
	pipe
	inherit
	ignore
}

struct ChildProcessSyncOptions {
mut:
	cwd      string
	env      map[string]string
	env_set  bool
	stdio    ChildProcessStdioMode = .pipe
	encoding string                = 'utf8'
	shell    string
	use_shell bool
}

struct ChildProcessRunResult {
	status int
	pid    int
	stdout string
	stderr string
}

struct ChildProcessAsyncInvocation {
mut:
	argv     []string
	options  ChildProcessSyncOptions
	callback Value
}

struct ChildProcessForkInvocation {
mut:
	module_path string
	argv        []string
	options     ChildProcessSyncOptions
	exec_path   string
	exec_argv   []string
}

fn candidate_command_paths(path string, roots []string) []string {
	mut candidates := []string{}
	if os.is_abs_path(path) {
		candidates << path
		return candidates
	}
	candidates << path
	for root in roots {
		candidates << os.join_path(root, path)
	}
	return candidates
}

fn resolve_child_process_command(command string, roots []string) !string {
	if command.contains(os.path_separator) || command.contains('/') || command.contains('\\') {
		for candidate in candidate_command_paths(command, roots) {
			if os.exists(candidate) {
				return os.real_path(candidate)
			}
		}
		return error('command not found: ${command}')
	}
	return os.find_abs_path_of_executable(command) or { error('command not found: ${command}') }
}

fn child_process_resolve_module_path(module_path string, cwd string, roots []string) string {
	if os.is_abs_path(module_path) {
		return module_path
	}
	if cwd != '' {
		return os.join_path(cwd, module_path)
	}
	if roots.len > 0 {
		return os.join_path(roots[0], module_path)
	}
	return module_path
}

fn child_process_string_array(value Value) ![]string {
	if !value.is_array() {
		return error('args must be an array')
	}
	mut items := []string{cap: value.len()}
	for i in 0 .. value.len() {
		part := value.get(i)
		items << part.str()
		part.free()
	}
	return items
}

fn child_process_env_map(value Value) map[string]string {
	mut env := map[string]string{}
	if !value.is_object() {
		return env
	}
	props := value.property_names() or { return env }
	for prop in props {
		key := prop.atom.str()
		entry := value.get(prop)
		if !entry.is_undefined() {
			env[key] = entry.str()
		}
		entry.free()
	}
	return env
}

fn child_process_stdio_mode(value Value) !ChildProcessStdioMode {
	if value.is_undefined() || value.is_null() {
		return .pipe
	}
	if value.is_string() {
		return match value.str() {
			'pipe' { .pipe }
			'inherit' { .inherit }
			'ignore' { .ignore }
			else { error('options.stdio must be "pipe", "inherit", or "ignore"') }
		}
	}
	if value.is_array() && value.len() > 0 {
		first := value.get(0)
		defer {
			first.free()
		}
		return child_process_stdio_mode(first)
	}
	return error('options.stdio must be a string or array')
}

fn child_process_sync_options(value Value) !ChildProcessSyncOptions {
	if value.is_undefined() || value.is_null() {
		return ChildProcessSyncOptions{}
	}
	if !value.is_object() {
		return error('options must be an object')
	}
	mut options := ChildProcessSyncOptions{}
	cwd_value := value.get('cwd')
	if !cwd_value.is_undefined() && !cwd_value.is_null() {
		if !cwd_value.is_string() {
			cwd_value.free()
			return error('options.cwd must be a string')
		}
		options.cwd = cwd_value.str()
	}
	cwd_value.free()
	env_value := value.get('env')
	if !env_value.is_undefined() && !env_value.is_null() {
		if !env_value.is_object() {
			env_value.free()
			return error('options.env must be an object')
		}
		options.env = child_process_env_map(env_value)
		options.env_set = true
	}
	env_value.free()
	stdio_value := value.get('stdio')
	options.stdio = child_process_stdio_mode(stdio_value)!
	stdio_value.free()
	encoding_value := value.get('encoding')
	if !encoding_value.is_undefined() && !encoding_value.is_null() {
		if !encoding_value.is_string() {
			encoding_value.free()
			return error('options.encoding must be a string')
		}
		options.encoding = encoding_value.str()
	}
	encoding_value.free()
	shell_value := value.get('shell')
	if !shell_value.is_undefined() && !shell_value.is_null() {
		if shell_value.is_bool() {
			options.use_shell = shell_value.to_bool()
		} else if shell_value.is_string() {
			options.use_shell = true
			options.shell = shell_value.str()
		} else {
			shell_value.free()
			return error('options.shell must be a boolean or string')
		}
	}
	shell_value.free()
	return options
}

fn child_process_fork_invocation(ctx &Context, args []Value) !ChildProcessForkInvocation {
	if args.len == 0 {
		return error('modulePath is required')
	}
	if !args[0].is_string() {
		return error('modulePath must be a string')
	}
	mut invocation := ChildProcessForkInvocation{
		module_path: args[0].str()
		options: ChildProcessSyncOptions{}
		exec_path: ''
		exec_argv: []string{}
	}
	mut options_index := -1
	if args.len > 1 && !args[1].is_undefined() && !args[1].is_null() {
		if args[1].is_array() {
			invocation.argv = child_process_string_array(args[1])!
			if args.len > 2 && !args[2].is_undefined() && !args[2].is_null() {
				options_index = 2
			}
		} else if args[1].is_object() {
			options_index = 1
		} else {
			return error('args must be an array or options object')
		}
	}
	if options_index >= 0 {
		options_value := args[options_index]
		invocation.options = child_process_sync_options(options_value)!
		exec_path_value := options_value.get('execPath')
		if !exec_path_value.is_undefined() && !exec_path_value.is_null() {
			if !exec_path_value.is_string() {
				exec_path_value.free()
				return error('options.execPath must be a string')
			}
			invocation.exec_path = exec_path_value.str()
		}
		exec_path_value.free()
		exec_argv_value := options_value.get('execArgv')
		if !exec_argv_value.is_undefined() && !exec_argv_value.is_null() {
			invocation.exec_argv = child_process_string_array(exec_argv_value)!
		}
		exec_argv_value.free()
	}
	return invocation
}

fn child_process_buffer_value(ctx &Context, text string) Value {
	if text.len == 0 {
		uint_cls := ctx.js_global('Uint8Array')
		arr := uint_cls.new(0)
		buffer := arr.get('buffer')
		arr.free()
		uint_cls.free()
		return buffer
	}
	return ctx.js_array_buffer(text.bytes())
}

fn child_process_output_value(ctx &Context, text string, encoding string) Value {
	if encoding == 'buffer' {
		return child_process_buffer_value(ctx, text)
	}
	return ctx.js_string(text)
}

fn child_process_exec_callback_error_value(ctx &Context, command string, args []string, result ChildProcessRunResult, encoding string) Value {
	mut err := child_process_error_value(ctx, command, args, result)
	stdout_value := child_process_output_value(ctx, result.stdout, encoding)
	stderr_value := child_process_output_value(ctx, result.stderr, encoding)
	err.set('stdout', stdout_value)
	err.set('stderr', stderr_value)
	mut output := ctx.js_array()
	output.set(0, ctx.js_null())
	output.set(1, stdout_value)
	output.set(2, stderr_value)
	err.set('output', output)
	output.free()
	stdout_value.free()
	stderr_value.free()
	return err
}

fn child_process_clone_callback(value Value) Value {
	if value.is_function() {
		return value.dup_value()
	}
	return value.ctx.js_undefined()
}

fn child_process_call_this(ctx &Context, this Value, callback Value, args []Value) !Value {
	c_args := args.map(it.dup_value().ref)
	c_val := if c_args.len == 0 { unsafe { nil } } else { &c_args[0] }
	ret := ctx.c_val(C.JS_Call(ctx.ref, callback.ref, this.ref, c_args.len, c_val))
	if ret.is_exception() {
		return ctx.js_exception()
	}
	return ret
}

fn child_process_event_bucket(ctx &Context, emitter Value, event string) Value {
	events := emitter.get('_vjsxEvents')
	mut listeners := events.get(event)
	if listeners.is_undefined() || listeners.is_null() {
		listeners.free()
		listeners = ctx.js_array()
		events.set(event, listeners)
	}
	events.free()
	return listeners
}

fn child_process_emit(ctx &Context, emitter Value, event string, args []Value) {
	events := emitter.get('_vjsxEvents')
	listeners := events.get(event)
	if listeners.is_undefined() || listeners.is_null() {
		listeners.free()
		events.free()
		return
	}
	mut next_listeners := ctx.js_array()
	for i in 0 .. listeners.len() {
		entry := listeners.get(i)
		callback := entry.get('callback')
		once_value := entry.get('once')
		is_once := once_value.to_bool()
		once_value.free()
		if callback.is_function() {
			call_result := child_process_call_this(ctx, emitter, callback, args) or {
				ctx.js_undefined()
			}
			call_result.free()
		}
		if !is_once {
			next_listeners.set(next_listeners.len(), entry)
		}
		callback.free()
		entry.free()
	}
	events.set(event, next_listeners)
	next_listeners.free()
	listeners.free()
	events.free()
}

fn child_process_filtered_listeners(ctx &Context, listeners Value, callback Value, remove_all bool) Value {
	mut next_listeners := ctx.js_array()
	for i in 0 .. listeners.len() {
		entry := listeners.get(i)
		entry_callback := entry.get('callback')
		should_remove := remove_all || (callback.is_function() && entry_callback.strict_eq(callback))
		if !should_remove {
			next_listeners.set(next_listeners.len(), entry)
		}
		entry_callback.free()
		entry.free()
	}
	return next_listeners
}

fn child_process_event_emitter(ctx &Context) Value {
	emitter := ctx.js_object()
	events := ctx.js_object()
	on_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len < 2 || !args[1].is_function() {
			return ctx.js_throw(ctx.js_error(
				message: 'event name and callback are required'
				name:    'TypeError'
			))
		}
		listeners := child_process_event_bucket(ctx, this, args[0].str())
		entry := ctx.js_object()
		entry.set('callback', args[1])
		entry.set('once', false)
		listeners.set(listeners.len(), entry)
		entry.free()
		listeners.free()
		return this.dup_value()
	})
	once_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len < 2 || !args[1].is_function() {
			return ctx.js_throw(ctx.js_error(
				message: 'event name and callback are required'
				name:    'TypeError'
			))
		}
		listeners := child_process_event_bucket(ctx, this, args[0].str())
		entry := ctx.js_object()
		entry.set('callback', args[1])
		entry.set('once', true)
		listeners.set(listeners.len(), entry)
		entry.free()
		listeners.free()
		return this.dup_value()
	})
	off_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len < 2 || !args[1].is_function() {
			return this.dup_value()
		}
		events := this.get('_vjsxEvents')
		listeners := events.get(args[0].str())
		if listeners.is_undefined() || listeners.is_null() {
			listeners.free()
			events.free()
			return this.dup_value()
		}
		next_listeners := child_process_filtered_listeners(ctx, listeners, args[1], false)
		events.set(args[0].str(), next_listeners)
		next_listeners.free()
		listeners.free()
		events.free()
		return this.dup_value()
	})
	remove_all_listeners_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		events := this.get('_vjsxEvents')
		if args.len == 0 || args[0].is_undefined() || args[0].is_null() {
			this.set('_vjsxEvents', ctx.js_object())
			events.free()
			return this.dup_value()
		}
		events.set(args[0].str(), ctx.js_array())
		events.free()
		return this.dup_value()
	})
	listeners_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len == 0 {
			return ctx.js_array()
		}
		listeners := child_process_event_bucket(ctx, this, args[0].str())
		mut callbacks := ctx.js_array()
		for i in 0 .. listeners.len() {
			entry := listeners.get(i)
			callback := entry.get('callback')
			callbacks.set(callbacks.len(), callback)
			callback.free()
			entry.free()
		}
		listeners.free()
		return callbacks
	})
	listener_count_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len == 0 {
			return ctx.js_int(0)
		}
		listeners := child_process_event_bucket(ctx, this, args[0].str())
		count := listeners.len()
		listeners.free()
		return ctx.js_int(count)
	})
	emit_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len == 0 {
			return ctx.js_bool(false)
		}
		event_name := args[0].str()
		events := this.get('_vjsxEvents')
		listeners := events.get(event_name)
		has_listeners := !listeners.is_undefined() && !listeners.is_null() && listeners.len() > 0
		listeners.free()
		events.free()
		if args.len > 1 {
			mut emit_args := []Value{cap: args.len - 1}
			for i in 1 .. args.len {
				emit_args << args[i]
			}
			child_process_emit(ctx, this, event_name, emit_args)
		} else {
			child_process_emit(ctx, this, event_name, []Value{})
		}
		return ctx.js_bool(has_listeners)
	})
	emitter.set('_vjsxEvents', events)
	emitter.set('on', on_fn)
	emitter.set('addListener', on_fn)
	emitter.set('once', once_fn)
	emitter.set('off', off_fn)
	emitter.set('removeListener', off_fn)
	emitter.set('removeAllListeners', remove_all_listeners_fn)
	emitter.set('listeners', listeners_fn)
	emitter.set('listenerCount', listener_count_fn)
	emitter.set('emit', emit_fn)
	events.free()
	on_fn.free()
	once_fn.free()
	off_fn.free()
	remove_all_listeners_fn.free()
	listeners_fn.free()
	listener_count_fn.free()
	emit_fn.free()
	return emitter
}

fn child_process_stream_object(ctx &Context) Value {
	stream := child_process_event_emitter(ctx)
	set_encoding_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len > 0 {
			this.set('_vjsxEncoding', args[0].str())
		}
		return this.dup_value()
	})
	resume_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		return this.dup_value()
	})
	pause_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		return this.dup_value()
	})
	pipe_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		if args.len == 0 || !args[0].is_object() {
			return ctx.js_throw(ctx.js_error(
				message: 'destination stream is required'
				name:    'TypeError'
			))
		}
		end_destination := if args.len > 1 {
			bool_option(args[1], 'end', true) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		} else {
			true
		}
		pipe_dests := this.get('_vjsxPipeDests')
		entry := ctx.js_object()
		entry.set('dest', args[0])
		entry.set('end', end_destination)
		pipe_dests.set(pipe_dests.len(), entry)
		entry.free()
		pipe_dests.free()
		return args[0].dup_value()
	})
	unpipe_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		pipe_dests := this.get('_vjsxPipeDests')
		if args.len == 0 || args[0].is_undefined() || args[0].is_null() {
			this.set('_vjsxPipeDests', ctx.js_array())
			pipe_dests.free()
			return this.dup_value()
		}
		if !args[0].is_object() {
			pipe_dests.free()
			return ctx.js_throw(ctx.js_error(
				message: 'destination stream is required'
				name:    'TypeError'
			))
		}
		mut next_dests := ctx.js_array()
		for i in 0 .. pipe_dests.len() {
			entry := pipe_dests.get(i)
			dest := entry.get('dest')
			if !dest.strict_eq(args[0]) {
				next_dests.set(next_dests.len(), entry)
			}
			dest.free()
			entry.free()
		}
		this.set('_vjsxPipeDests', next_dests)
		next_dests.free()
		pipe_dests.free()
		return this.dup_value()
	})
	stream.set('_vjsxEncoding', 'utf8')
	stream.set('_vjsxPipeDests', ctx.js_array())
	stream.set('readable', true)
	stream.set('setEncoding', set_encoding_fn)
	stream.set('resume', resume_fn)
	stream.set('pause', pause_fn)
	stream.set('pipe', pipe_fn)
	stream.set('unpipe', unpipe_fn)
	set_encoding_fn.free()
	resume_fn.free()
	pause_fn.free()
	pipe_fn.free()
	unpipe_fn.free()
	return stream
}

fn child_process_pipe_stream_chunk(ctx &Context, stream Value, chunk Value) {
	pipe_dests := stream.get('_vjsxPipeDests')
	defer {
		pipe_dests.free()
	}
	for i in 0 .. pipe_dests.len() {
		entry := pipe_dests.get(i)
		dest := entry.get('dest')
		if dest.is_object() {
			write_result := dest.call('write', chunk)
			write_result.free()
		}
		dest.free()
		entry.free()
	}
}

fn child_process_finish_piped_stream(ctx &Context, stream Value) {
	pipe_dests := stream.get('_vjsxPipeDests')
	defer {
		pipe_dests.free()
	}
	for i in 0 .. pipe_dests.len() {
		entry := pipe_dests.get(i)
		end_value := entry.get('end')
		should_end := end_value.to_bool()
		end_value.free()
		dest := entry.get('dest')
		if should_end && dest.is_object() && dest.has('_vjsxFinishListeners') {
			fs_emit_finish(ctx, dest) or {}
		}
		dest.free()
		entry.free()
	}
}

fn child_process_emit_stream_data(ctx &Context, stream Value, text string) {
	if text == '' {
		return
	}
	encoding_value := stream.get('_vjsxEncoding')
	encoding := encoding_value.str()
	encoding_value.free()
	chunk := child_process_output_value(ctx, text, encoding)
	child_process_emit(ctx, stream, 'data', [chunk])
	child_process_pipe_stream_chunk(ctx, stream, chunk)
	chunk.free()
}

fn child_process_base_object(ctx &Context, command string, args []string) Value {
	child := child_process_event_emitter(ctx)
	stdout_stream := child_process_stream_object(ctx)
	stderr_stream := child_process_stream_object(ctx)
	stdin_stream := ctx.js_object()
	stdin_write_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		return ctx.js_bool(false)
	})
	stdin_end_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		return ctx.js_undefined()
	})
	kill_fn := ctx.js_function_this(fn [ctx] (this Value, args []Value) Value {
		return ctx.js_bool(false)
	})
	mut spawnargs := ctx.js_array()
	mut stdio := ctx.js_array()
	for i, arg in args {
		spawnargs.set(i, arg)
	}
	stdio.set(0, stdin_stream)
	stdio.set(1, stdout_stream)
	stdio.set(2, stderr_stream)
	child.set('pid', 0)
	child.set('killed', false)
	child.set('connected', false)
	child.set('exitCode', ctx.js_null())
	child.set('signalCode', ctx.js_null())
	child.set('spawnfile', command)
	child.set('spawnargs', spawnargs)
	child.set('stdout', stdout_stream)
	child.set('stderr', stderr_stream)
	child.set('stdin', stdin_stream)
	child.set('stdio', stdio)
	child.set('kill', kill_fn)
	stdin_stream.set('write', stdin_write_fn)
	stdin_stream.set('end', stdin_end_fn)
	spawnargs.free()
	stdio.free()
	stdout_stream.free()
	stderr_stream.free()
	stdin_stream.free()
	stdin_write_fn.free()
	stdin_end_fn.free()
	kill_fn.free()
	return child
}

fn child_process_schedule(ctx &Context, child Value) {
	timeout := ctx.js_global('setTimeout')
	if timeout.is_function() {
		child_ref := child.dup_value()
		runner := ctx.js_function(fn [ctx, child_ref] (args []Value) Value {
			mut target := child_ref
			child_process_flush_completion(ctx, target)
			target.free()
			return ctx.js_undefined()
		})
		call_result := ctx.call(timeout, runner, 0) or { ctx.js_undefined() }
		call_result.free()
		runner.free()
		timeout.free()
		return
	}
	timeout.free()
	child_process_flush_completion(ctx, child)
}

fn child_process_schedule_live(ctx &Context, child Value, mut proc os.Process, redirect_stdio bool) {
	timeout := ctx.js_global('setTimeout')
	if !timeout.is_function() {
		timeout.free()
		mut process_ref := proc
		mut child_ref := child
		child_process_poll_live(ctx, mut child_ref, mut process_ref, redirect_stdio)
		return
	}
	child_ref := child.dup_value()
	runner := ctx.js_function(fn [ctx, child_ref, mut proc, redirect_stdio] (args []Value) Value {
		mut target := child_ref
		mut process_ref := proc
		child_process_poll_live(ctx, mut target, mut process_ref, redirect_stdio)
		return ctx.js_undefined()
	})
	call_result := ctx.call(timeout, runner, 10) or { ctx.js_undefined() }
	call_result.free()
	runner.free()
	timeout.free()
}

fn child_process_poll_live(ctx &Context, mut child Value, mut proc os.Process, redirect_stdio bool) {
	done_value := child.get('_vjsxLiveDone')
	if done_value.to_bool() {
		done_value.free()
		return
	}
	done_value.free()
	mut saw_output := false
	if redirect_stdio {
		stdout_stream := child.get('stdout')
		stderr_stream := child.get('stderr')
		for proc.is_pending(.stdout) {
			chunk := proc.stdout_read()
			if chunk == '' {
				break
			}
			child_process_emit_stream_data(ctx, stdout_stream, chunk)
			saw_output = true
		}
		for proc.is_pending(.stderr) {
			chunk := proc.stderr_read()
			if chunk == '' {
				break
			}
			child_process_emit_stream_data(ctx, stderr_stream, chunk)
			saw_output = true
		}
		stdout_stream.free()
		stderr_stream.free()
	}
	killed_value := child.get('killed')
	was_killed := killed_value.to_bool()
	killed_value.free()
	if was_killed {
		proc.wait()
		if redirect_stdio {
			stdout_stream := child.get('stdout')
			stderr_stream := child.get('stderr')
			for proc.is_pending(.stdout) {
				chunk := proc.stdout_read()
				if chunk == '' {
					break
				}
				child_process_emit_stream_data(ctx, stdout_stream, chunk)
			}
			for proc.is_pending(.stderr) {
				chunk := proc.stderr_read()
				if chunk == '' {
					break
				}
				child_process_emit_stream_data(ctx, stderr_stream, chunk)
			}
			child_process_emit(ctx, stdout_stream, 'end', []Value{})
			child_process_emit(ctx, stderr_stream, 'end', []Value{})
			child_process_finish_piped_stream(ctx, stdout_stream)
			child_process_finish_piped_stream(ctx, stderr_stream)
			child_process_emit(ctx, stdout_stream, 'close', []Value{})
			child_process_emit(ctx, stderr_stream, 'close', []Value{})
			stdout_stream.free()
			stderr_stream.free()
		}
		child.set('_vjsxLiveDone', true)
		code_value := child.get('exitCode')
		final_signal_value := child.get('signalCode')
		child_process_emit(ctx, child, 'exit', [code_value, final_signal_value])
		child_process_emit(ctx, child, 'close', [code_value, final_signal_value])
		code_value.free()
		final_signal_value.free()
		proc.close()
		return
	}
	idle_polls_value := child.get('_vjsxIdlePolls')
	mut idle_polls := idle_polls_value.to_int()
	idle_polls_value.free()
	if saw_output {
		idle_polls = 0
	} else {
		idle_polls++
	}
	child.set('_vjsxIdlePolls', idle_polls)
	if idle_polls >= 5 {
		proc.wait()
		if redirect_stdio {
			stdout_stream := child.get('stdout')
			stderr_stream := child.get('stderr')
			for proc.is_pending(.stdout) {
				chunk := proc.stdout_read()
				if chunk == '' {
					break
				}
				child_process_emit_stream_data(ctx, stdout_stream, chunk)
			}
			for proc.is_pending(.stderr) {
				chunk := proc.stderr_read()
				if chunk == '' {
					break
				}
				child_process_emit_stream_data(ctx, stderr_stream, chunk)
			}
			child_process_emit(ctx, stdout_stream, 'end', []Value{})
			child_process_emit(ctx, stderr_stream, 'end', []Value{})
			child_process_finish_piped_stream(ctx, stdout_stream)
			child_process_finish_piped_stream(ctx, stderr_stream)
			child_process_emit(ctx, stdout_stream, 'close', []Value{})
			child_process_emit(ctx, stderr_stream, 'close', []Value{})
			stdout_stream.free()
			stderr_stream.free()
		}
		child.set('_vjsxLiveDone', true)
		child.set('exitCode', ctx.js_int(proc.code))
		child.set('signalCode', ctx.js_null())
		code_value := child.get('exitCode')
		final_signal_value := child.get('signalCode')
		child_process_emit(ctx, child, 'exit', [code_value, final_signal_value])
		child_process_emit(ctx, child, 'close', [code_value, final_signal_value])
		code_value.free()
		final_signal_value.free()
		proc.close()
		return
	}
	if proc.is_alive() {
		child_process_schedule_live(ctx, child, mut proc, redirect_stdio)
		return
	}
	proc.wait()
	if redirect_stdio {
		stdout_stream := child.get('stdout')
		stderr_stream := child.get('stderr')
		for proc.is_pending(.stdout) {
			chunk := proc.stdout_read()
			if chunk == '' {
				break
			}
			child_process_emit_stream_data(ctx, stdout_stream, chunk)
		}
		for proc.is_pending(.stderr) {
			chunk := proc.stderr_read()
			if chunk == '' {
				break
			}
			child_process_emit_stream_data(ctx, stderr_stream, chunk)
		}
		child_process_emit(ctx, stdout_stream, 'end', []Value{})
		child_process_emit(ctx, stderr_stream, 'end', []Value{})
		child_process_finish_piped_stream(ctx, stdout_stream)
		child_process_finish_piped_stream(ctx, stderr_stream)
		child_process_emit(ctx, stdout_stream, 'close', []Value{})
		child_process_emit(ctx, stderr_stream, 'close', []Value{})
		stdout_stream.free()
		stderr_stream.free()
	}
	signal_value := child.get('signalCode')
	has_signal := !signal_value.is_null() && !signal_value.is_undefined()
	signal_value.free()
	if has_signal {
		child.set('exitCode', ctx.js_null())
	} else {
		child.set('exitCode', ctx.js_int(proc.code))
	}
	child.set('_vjsxLiveDone', true)
	code_value := child.get('exitCode')
	final_signal_value := child.get('signalCode')
	child_process_emit(ctx, child, 'exit', [code_value, final_signal_value])
	child_process_emit(ctx, child, 'close', [code_value, final_signal_value])
	code_value.free()
	final_signal_value.free()
	proc.close()
}

fn child_process_flush_completion(ctx &Context, child Value) {
	flushed := child.get('_vjsxFlushed')
	if flushed.to_bool() {
		flushed.free()
		return
	}
	flushed.free()
	child.set('_vjsxFlushed', true)
	stdout_text_value := child.get('_vjsxStdoutText')
	stderr_text_value := child.get('_vjsxStderrText')
	stdout_text := stdout_text_value.str()
	stderr_text := stderr_text_value.str()
	stdout_text_value.free()
	stderr_text_value.free()
	stdout_stream := child.get('stdout')
	stderr_stream := child.get('stderr')
	if stdout_text != '' {
		child_process_emit_stream_data(ctx, stdout_stream, stdout_text)
	}
	if stderr_text != '' {
		child_process_emit_stream_data(ctx, stderr_stream, stderr_text)
	}
	child_process_emit(ctx, stdout_stream, 'end', []Value{})
	child_process_emit(ctx, stderr_stream, 'end', []Value{})
	child_process_finish_piped_stream(ctx, stdout_stream)
	child_process_finish_piped_stream(ctx, stderr_stream)
	child_process_emit(ctx, stdout_stream, 'close', []Value{})
	child_process_emit(ctx, stderr_stream, 'close', []Value{})
	stdout_stream.free()
	stderr_stream.free()

	callback_value := child.get('_vjsxCallback')
	callback_encoding := child.get('_vjsxEncoding').str()
	if callback_value.is_function() {
		stdout_output := child_process_output_value(ctx, stdout_text, callback_encoding)
		stderr_output := child_process_output_value(ctx, stderr_text, callback_encoding)
		callback_error := child.get('_vjsxCallbackError')
		call_result := if callback_error.is_undefined() || callback_error.is_null() {
			ctx.call_this(child, callback_value, ctx.js_null(), stdout_output, stderr_output) or {
				ctx.js_undefined()
			}
		} else {
			ctx.call_this(child, callback_value, callback_error, stdout_output, stderr_output) or {
				ctx.js_undefined()
			}
		}
		call_result.free()
		callback_error.free()
		stdout_output.free()
		stderr_output.free()
	}
	callback_value.free()

	spawn_error := child.get('_vjsxSpawnError')
	if !spawn_error.is_undefined() && !spawn_error.is_null() {
		child_process_emit(ctx, child, 'error', [spawn_error])
	}
	code_value := child.get('exitCode')
	signal_value := child.get('signalCode')
	if spawn_error.is_undefined() || spawn_error.is_null() {
		child_process_emit(ctx, child, 'exit', [code_value, signal_value])
	}
	child_process_emit(ctx, child, 'close', [code_value, signal_value])
	code_value.free()
	signal_value.free()
	spawn_error.free()
}

fn child_process_exec_file_invocation(ctx &Context, args []Value) !ChildProcessAsyncInvocation {
	mut invocation := ChildProcessAsyncInvocation{
		callback: ctx.js_undefined()
	}
	mut callback_index := -1
	if args.len > 0 && args[args.len - 1].is_function() {
		callback_index = args.len - 1
		invocation.callback = child_process_clone_callback(args[callback_index])
	} else {
		invocation.callback = ctx.js_undefined()
	}
	limit := if callback_index >= 0 { callback_index } else { args.len }
	if limit > 1 && !args[1].is_undefined() && !args[1].is_null() {
		if args[1].is_array() {
			invocation.argv = child_process_string_array(args[1])!
			if limit > 2 {
				invocation.options = child_process_sync_options(args[2])!
			}
		} else if args[1].is_object() {
			invocation.options = child_process_sync_options(args[1])!
		} else {
			return error('args must be an array or options object')
		}
	}
	return invocation
}

fn child_process_exec_invocation(ctx &Context, args []Value) !ChildProcessAsyncInvocation {
	mut invocation := ChildProcessAsyncInvocation{
		callback: ctx.js_undefined()
	}
	mut callback_index := -1
	if args.len > 0 && args[args.len - 1].is_function() {
		callback_index = args.len - 1
		invocation.callback = child_process_clone_callback(args[callback_index])
	} else {
		invocation.callback = ctx.js_undefined()
	}
	limit := if callback_index >= 0 { callback_index } else { args.len }
	if limit > 1 && !args[1].is_undefined() && !args[1].is_null() {
		if !args[1].is_object() {
			return error('options must be an object')
		}
		invocation.options = child_process_sync_options(args[1])!
	} else {
		invocation.options = ChildProcessSyncOptions{}
	}
	return invocation
}

fn child_process_shell_path(override string) string {
	if override != '' {
		return override
	}
	$if windows {
		return 'cmd'
	} $else {
		return 'sh'
	}
}

fn child_process_shell_command(command string, shell_override string) (string, []string) {
	shell_path := child_process_shell_path(shell_override)
	$if windows {
		return shell_path, ['/d', '/c', command]
	} $else {
		return shell_path, ['-lc', command]
	}
}

fn child_process_shell_escape_arg(arg string) string {
	$if windows {
		if arg == '' {
			return '""'
		}
		escaped := arg.replace('"', '\\"')
		if escaped.contains(' ') || escaped.contains('\t') || escaped.contains('"') {
			return '"${escaped}"'
		}
		return escaped
	} $else {
		if arg == '' {
			return "''"
		}
		return "'" + arg.replace("'", "'\"'\"'") + "'"
	}
}

fn child_process_shell_command_line(command string, args []string) string {
	mut parts := []string{cap: args.len + 1}
	parts << command
	for arg in args {
		parts << child_process_shell_escape_arg(arg)
	}
	return parts.join(' ')
}

fn child_process_apply_shell(command string, args []string, options ChildProcessSyncOptions) (string, []string) {
	if !options.use_shell {
		return command, args
	}
	command_line := child_process_shell_command_line(command, args)
	return child_process_shell_command(command_line, options.shell)
}

fn child_process_without_shell(options ChildProcessSyncOptions) ChildProcessSyncOptions {
	mut next := options
	next.use_shell = false
	next.shell = ''
	return next
}

fn child_process_run(command string, args []string, options ChildProcessSyncOptions, roots []string) !ChildProcessRunResult {
	final_command, final_args := child_process_apply_shell(command, args, options)
	resolved := resolve_child_process_command(final_command, roots)!
	mut proc := os.new_process(resolved)
	proc.set_args(final_args)
	if options.cwd != '' {
		proc.set_work_folder(options.cwd)
	}
	if options.env_set {
		proc.set_environment(options.env)
	}
	if options.stdio != .inherit {
		proc.set_redirect_stdio()
	}
	proc.run()
	mut stdout := ''
	mut stderr := ''
	if options.stdio != .inherit {
		stdout = proc.stdout_slurp()
		stderr = proc.stderr_slurp()
	}
	proc.wait()
	pid := proc.pid
	status := proc.code
	proc.close()
	if options.stdio == .ignore {
		stdout = ''
		stderr = ''
	}
	return ChildProcessRunResult{
		status: status
		pid:    pid
		stdout: stdout
		stderr: stderr
	}
}

fn child_process_error_value(ctx &Context, command string, args []string, result ChildProcessRunResult) Value {
	mut err := ctx.js_error(message: 'Command failed: ${command}')
	err.set('status', ctx.js_int(result.status))
	err.set('pid', ctx.js_int(result.pid))
	err.set('stdout', ctx.js_string(result.stdout))
	err.set('stderr', ctx.js_string(result.stderr))
	mut output := ctx.js_array()
	output.set(0, ctx.js_null())
	output.set(1, ctx.js_string(result.stdout))
	output.set(2, ctx.js_string(result.stderr))
	err.set('output', output)
	err.set('signal', ctx.js_null())
	err.set('path', ctx.js_string(command))
	mut spawnargs := ctx.js_array()
	for i, arg in args {
		spawnargs.set(i, arg)
	}
	err.set('spawnargs', spawnargs)
	output.free()
	spawnargs.free()
	return err
}

fn child_process_spawn_sync_result_value(ctx &Context, result ChildProcessRunResult, command string, args []string) Value {
	mut value := ctx.js_object()
	value.set('pid', ctx.js_int(result.pid))
	value.set('status', ctx.js_int(result.status))
	value.set('signal', ctx.js_null())
	value.set('stdout', ctx.js_string(result.stdout))
	value.set('stderr', ctx.js_string(result.stderr))
	mut output := ctx.js_array()
	output.set(0, ctx.js_null())
	output.set(1, ctx.js_string(result.stdout))
	output.set(2, ctx.js_string(result.stderr))
	value.set('output', output)
	value.set('path', ctx.js_string(command))
	mut spawnargs := ctx.js_array()
	for i, arg in args {
		spawnargs.set(i, arg)
	}
	value.set('spawnargs', spawnargs)
	output.free()
	spawnargs.free()
	return value
}

fn child_process_exec_result_value(ctx &Context, result ChildProcessRunResult, encoding string) Value {
	if encoding == 'buffer' {
		return child_process_buffer_value(ctx, result.stdout)
	}
	return ctx.js_string(result.stdout)
}

fn child_process_async_result_object(ctx &Context, command string, args []string, result ChildProcessRunResult, options ChildProcessSyncOptions, callback Value) Value {
	child := child_process_base_object(ctx, command, args)
	child.set('pid', ctx.js_int(result.pid))
	child.set('exitCode', ctx.js_int(result.status))
	child.set('_vjsxStdoutText', result.stdout)
	child.set('_vjsxStderrText', result.stderr)
	child.set('_vjsxEncoding', options.encoding)
	child.set('_vjsxCallback', callback)
	child.set('_vjsxCallbackError', if result.status == 0 {
		ctx.js_null()
	} else {
		child_process_exec_callback_error_value(ctx, command, args, result, options.encoding)
	})
	child.set('_vjsxSpawnError', ctx.js_null())
	child.set('_vjsxFlushed', false)
	return child
}

fn child_process_async_spawn_error_object(ctx &Context, command string, args []string, callback Value, message string) Value {
	child := child_process_base_object(ctx, command, args)
	child.set('_vjsxStdoutText', '')
	child.set('_vjsxStderrText', '')
	child.set('_vjsxEncoding', 'utf8')
	child.set('_vjsxCallback', callback)
	child.set('_vjsxCallbackError', ctx.js_null())
	child.set('_vjsxSpawnError', ctx.js_error(message: message))
	child.set('_vjsxFlushed', false)
	return child
}

fn child_process_spawn_live(ctx &Context, command string, args []string, options ChildProcessSyncOptions, roots []string) !Value {
	final_command, final_args := child_process_apply_shell(command, args, options)
	resolved := resolve_child_process_command(final_command, roots)!
	mut proc := os.new_process(resolved)
	proc.set_args(final_args)
	if options.cwd != '' {
		proc.set_work_folder(options.cwd)
	}
	if options.env_set {
		proc.set_environment(options.env)
	}
	redirect_stdio := options.stdio == .pipe
	if redirect_stdio {
		proc.set_redirect_stdio()
	}
	proc.run()
	child := child_process_base_object(ctx, command, args)
	child_ref := child.dup_value()
	child.set('pid', ctx.js_int(proc.pid))
	child.set('_vjsxLiveDone', false)
	child.set('_vjsxIdlePolls', 0)
	child.set('_vjsxEncoding', options.encoding)
	child.set('_vjsxSpawnError', ctx.js_null())
	stdin_stream := child.get('stdin')
	stdin_write_fn := ctx.js_function_this(fn [ctx, child_ref, mut proc, redirect_stdio] (this Value, args []Value) Value {
		if !redirect_stdio {
			return ctx.js_bool(false)
		}
		if args.len == 0 {
			return ctx.js_bool(true)
		}
		data := if args[0].is_string() { args[0].str() } else { args[0].to_string() }
		mut process_ref := proc
		process_ref.stdin_write(data)
		if args.len > 1 && args[1].is_function() {
			call_result := ctx.call_this(child_ref, args[1]) or { ctx.js_undefined() }
			call_result.free()
		}
		return ctx.js_bool(true)
	})
	stdin_end_fn := ctx.js_function_this(fn [ctx, child_ref, mut proc, redirect_stdio] (this Value, args []Value) Value {
		if !redirect_stdio {
			return ctx.js_undefined()
		}
		if args.len > 0 && !args[0].is_function() {
			data := if args[0].is_string() { args[0].str() } else { args[0].to_string() }
			mut process_ref := proc
			process_ref.stdin_write(data)
		}
		callback := if args.len > 0 && args[args.len - 1].is_function() { args[args.len - 1] } else { ctx.js_undefined() }
		if callback.is_function() {
			call_result := ctx.call_this(child_ref, callback) or { ctx.js_undefined() }
			call_result.free()
		}
		this.set('writable', false)
		return ctx.js_undefined()
	})
	stdin_stream.set('write', stdin_write_fn)
	stdin_stream.set('end', stdin_end_fn)
	stdin_stream.set('writable', true)
	stdin_write_fn.free()
	stdin_end_fn.free()
	stdin_stream.free()
	kill_fn := ctx.js_function_this(fn [ctx, child_ref, mut proc] (this Value, args []Value) Value {
		signal := if args.len > 0 && args[0].is_string() && args[0].str() != '' { args[0].str() } else { 'SIGTERM' }
		mut process_ref := proc
		match signal {
			'SIGKILL' {
				process_ref.signal_kill()
			}
			'SIGSTOP' {
				process_ref.signal_stop()
			}
			'SIGCONT' {
				process_ref.signal_continue()
			}
			else {
				process_ref.signal_term()
			}
		}
		child_ref.set('killed', signal in ['SIGTERM', 'SIGKILL'])
		child_ref.set('signalCode', signal)
		child_ref.set('exitCode', ctx.js_null())
		return ctx.js_bool(true)
	})
	child.set('kill', kill_fn)
	kill_fn.free()
	ctx.register_host_cleanup(fn [mut proc] () {
		if proc.status in [.running, .stopped] {
			proc.signal_kill()
		}
		proc.close()
	})
	child_process_schedule_live(ctx, child, mut proc, redirect_stdio)
	return child
}

fn child_process_default_fork_exec_path() !string {
	repo_root := os.getenv('VJS_REPO_ROOT')
	if repo_root != '' {
		candidate := os.join_path(repo_root, 'vjsx')
		if os.exists(candidate) {
			return candidate
		}
	}
	return error('unable to locate vjsx executable for fork()')
}

fn child_process_fork_command(invocation ChildProcessForkInvocation, roots []string) !(string, []string, ChildProcessSyncOptions) {
	exec_path := if invocation.exec_path != '' {
		invocation.exec_path
	} else {
		child_process_default_fork_exec_path()!
	}
	module_path := child_process_resolve_module_path(invocation.module_path, invocation.options.cwd, roots)
	mut argv := []string{}
	argv << invocation.exec_argv
	argv << module_path
	argv << invocation.argv
	mut options := invocation.options
	options.use_shell = false
	options.shell = ''
	return exec_path, argv, options
}

// Install a Node-like `child_process` module with common synchronous helpers.
pub fn (ctx &Context) install_child_process_module(roots []string) {
	mut child_process_mod := ctx.js_module('child_process')
	exec_file_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'file is required', name: 'TypeError'))
		}
		command := args[0].str()
		mut argv := []string{}
		mut options := ChildProcessSyncOptions{}
		if args.len > 1 && !args[1].is_undefined() && !args[1].is_null() {
			if args[1].is_array() {
				argv = child_process_string_array(args[1]) or {
					return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
				}
				if args.len > 2 {
					options = child_process_sync_options(args[2]) or {
						return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
					}
				}
			} else if args[1].is_object() {
				options = child_process_sync_options(args[1]) or {
					return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
				}
			} else {
				return ctx.js_throw(ctx.js_error(
					message: 'args must be an array or options object'
					name:    'TypeError'
				))
			}
		}
		result := child_process_run(command, argv, options, roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		if result.status != 0 {
			return ctx.js_throw(child_process_error_value(ctx, command, argv, result))
		}
		return child_process_exec_result_value(ctx, result, options.encoding)
	})
	exec_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'command is required', name: 'TypeError'))
		}
		command := args[0].str()
		options := if args.len > 1 {
			child_process_sync_options(args[1]) or {
				return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
			}
		} else {
			ChildProcessSyncOptions{}
		}
		shell_command, shell_args := child_process_shell_command(command, options.shell)
		result := child_process_run(shell_command, shell_args, child_process_without_shell(options),
			roots) or {
			return ctx.js_throw(ctx.js_error(message: err.msg()))
		}
		if result.status != 0 {
			return ctx.js_throw(child_process_error_value(ctx, shell_command, shell_args,
				result))
		}
		return child_process_exec_result_value(ctx, result, options.encoding)
	})
	spawn_sync := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'file is required', name: 'TypeError'))
		}
		command := args[0].str()
		mut argv := []string{}
		mut options := ChildProcessSyncOptions{}
		if args.len > 1 && !args[1].is_undefined() && !args[1].is_null() {
			if args[1].is_array() {
				argv = child_process_string_array(args[1]) or {
					return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
				}
				if args.len > 2 {
					options = child_process_sync_options(args[2]) or {
						return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
					}
				}
			} else if args[1].is_object() {
				options = child_process_sync_options(args[1]) or {
					return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
				}
			} else {
				return ctx.js_throw(ctx.js_error(
					message: 'args must be an array or options object'
					name:    'TypeError'
				))
			}
		}
		result := child_process_run(command, argv, options, roots) or {
			mut value := ctx.js_object()
			value.set('pid', ctx.js_int(0))
			value.set('status', ctx.js_null())
			value.set('signal', ctx.js_null())
			value.set('stdout', ctx.js_string(''))
			value.set('stderr', ctx.js_string(''))
			value.set('error', ctx.js_error(message: err.msg()))
			return value
		}
		return child_process_spawn_sync_result_value(ctx, result, command, argv)
	})
	exec_file := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'file is required', name: 'TypeError'))
		}
		command := args[0].str()
		invocation := child_process_exec_file_invocation(ctx, args) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		result := child_process_run(command, invocation.argv, invocation.options, roots) or {
			child := child_process_async_spawn_error_object(ctx, command, invocation.argv,
				invocation.callback, err.msg())
			child_process_schedule(ctx, child)
			return child
		}
		child := child_process_async_result_object(ctx, command, invocation.argv, result,
			invocation.options, invocation.callback)
		child_process_schedule(ctx, child)
		return child
	})
	exec_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'command is required', name: 'TypeError'))
		}
		command := args[0].str()
		invocation := child_process_exec_invocation(ctx, args) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		shell_command, shell_args := child_process_shell_command(command, invocation.options.shell)
		result := child_process_run(shell_command, shell_args,
			child_process_without_shell(invocation.options), roots) or {
			child := child_process_async_spawn_error_object(ctx, shell_command, shell_args,
				invocation.callback, err.msg())
			child_process_schedule(ctx, child)
			return child
		}
		child := child_process_async_result_object(ctx, shell_command, shell_args, result,
			invocation.options, invocation.callback)
		child_process_schedule(ctx, child)
		return child
	})
	spawn_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		if args.len == 0 {
			return ctx.js_throw(ctx.js_error(message: 'file is required', name: 'TypeError'))
		}
		command := args[0].str()
		invocation := child_process_exec_file_invocation(ctx, args) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		return child_process_spawn_live(ctx, command, invocation.argv, invocation.options,
			roots) or {
			child := child_process_async_spawn_error_object(ctx, command, invocation.argv,
				ctx.js_undefined(), err.msg())
			child_process_schedule(ctx, child)
			child
		}
	})
	fork_fn := ctx.js_function(fn [ctx, roots] (args []Value) Value {
		invocation := child_process_fork_invocation(ctx, args) or {
			return ctx.js_throw(ctx.js_error(message: err.msg(), name: 'TypeError'))
		}
		command, argv, options := child_process_fork_command(invocation, roots) or {
			child := child_process_async_spawn_error_object(ctx, invocation.module_path,
				invocation.argv, ctx.js_undefined(), err.msg())
			child_process_schedule(ctx, child)
			return child
		}
		return child_process_spawn_live(ctx, command, argv, options, roots) or {
			child := child_process_async_spawn_error_object(ctx, invocation.module_path,
				invocation.argv, ctx.js_undefined(), err.msg())
			child_process_schedule(ctx, child)
			child
		}
	})
	child_process_mod.export('execFile', exec_file)
	child_process_mod.export('exec', exec_fn)
	child_process_mod.export('spawn', spawn_fn)
	child_process_mod.export('fork', fork_fn)
	child_process_mod.export('execFileSync', exec_file_sync)
	child_process_mod.export('execSync', exec_sync)
	child_process_mod.export('spawnSync', spawn_sync)
	default_obj := ctx.js_object()
	default_obj.set('execFile', exec_file)
	default_obj.set('exec', exec_fn)
	default_obj.set('spawn', spawn_fn)
	default_obj.set('fork', fork_fn)
	default_obj.set('execFileSync', exec_file_sync)
	default_obj.set('execSync', exec_sync)
	default_obj.set('spawnSync', spawn_sync)
	child_process_mod.export_default(default_obj)
	child_process_mod.create()
	default_obj.free()
	exec_file.free()
	exec_fn.free()
	spawn_fn.free()
	fork_fn.free()
	exec_file_sync.free()
	exec_sync.free()
	spawn_sync.free()
}

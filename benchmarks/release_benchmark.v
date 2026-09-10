module main

import os
import runtimejs
import time
import vjsx

fn iterations() int {
	configured := os.getenv_opt('VJSX_BENCH_ITERATIONS') or { '25' }.int()
	return if configured < 1 { 1 } else { configured }
}

fn elapsed_ms(start i64) i64 {
	return time.ticks() - start
}

fn main() {
	count := iterations()
	mut started := time.ticks()
	for _ in 0 .. count {
		mut session := vjsx.try_new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{}) or { panic(err) }
		session.close()
	}
	startup_ms := elapsed_ms(started)

	mut compiler := vjsx.new_runtime_session()
	defer {
		compiler.close()
	}
	started = time.ticks()
	mut bytecode := []u8{}
	for _ in 0 .. count {
		bytecode = compiler.context().compile_module_bytecode('module.exports = { add: (a, b) => a + b };',
			filename: 'benchmark.js'
			runtime_profile: 'node'
		) or { panic(err) }
	}
	compile_ms := elapsed_ms(started)

	bundle := compiler.context().compile_bundle([
		vjsx.BundleSourceModule{
			name: 'vjsx-bundle/benchmark/main.mjs'
			source: 'export function add(a, b) { return a + b; }'
		},
	],
		app_name: 'benchmark'
		entry: 'vjsx-bundle/benchmark/main.mjs'
		runtime_profile: 'node'
	) or { panic(err) }
	started = time.ticks()
	for _ in 0 .. count {
		mut session := vjsx.try_new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{}) or { panic(err) }
		mut loaded := session.context().load_bundle(bundle) or { panic(err) }
		loaded.close()
		session.close()
	}
	bundle_load_ms := elapsed_ms(started)

	mut session := runtimejs.try_new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{}) or { panic(err) }
	defer {
		session.close()
	}
	mut loaded := session.context().load_bytecode(bytecode) or { panic(err) }
	defer {
		loaded.close()
	}
	started = time.ticks()
	for index in 0 .. count * 1000 {
		value := loaded.call_export('add', index, 1) or { panic(err) }
		value.free()
	}
	steady_call_ms := elapsed_ms(started)

	started = time.ticks()
	for index in 0 .. count * 100 {
		operation := session.start_host_async_operation(kind: 'benchmark-${index}') or { panic(err) }
		operation.promise.free()
		if !operation.completion.resolve_text('ok') {
			panic('benchmark completion was rejected')
		}
	}
	session.drain_host_async_events() or { panic(err) }
	session.drain_ready_tasks() or { panic(err) }
	async_schedule_ms := elapsed_ms(started)

	println('vjsx_release_benchmark iterations=${count}')
	println('startup_total_ms=${startup_ms}')
	println('compile_module_total_ms=${compile_ms}')
	println('bundle_load_total_ms=${bundle_load_ms}')
	println('steady_call_${count * 1000}_total_ms=${steady_call_ms}')
	println('async_schedule_${count * 100}_total_ms=${async_schedule_ms}')
}

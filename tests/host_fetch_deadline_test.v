import os
import time
import vjsx

fn test_fetch_deadline_returns_before_host_watchdog() {
	sw := time.new_stopwatch()
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{
			read_timeout:  1 * time.millisecond
			write_timeout: 1 * time.millisecond
			max_retries:   0
		}
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('fetch("http://192.0.2.1/").then(
		() => "resolved",
		(err) => "rejected:" + err.message
	)') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string().starts_with('rejected:')
	assert sw.elapsed() < 2 * time.second
}

fn test_fetch_uses_configured_curl() {
	temp_dir := os.join_path(os.temp_dir(), 'vjsx-fake-curl-${os.getpid()}')
	os.mkdir_all(temp_dir) or { panic(err) }
	defer {
		os.rmdir_all(temp_dir) or {}
	}
	curl_path := os.join_path(temp_dir, 'curl')
	os.write_file(curl_path,
		'#!/bin/sh\nheaders=""\nbody=""\nwhile [ "$#" -gt 0 ]; do\n  case "$1" in\n    -D) shift; headers="$1" ;;\n    -o) shift; body="$1" ;;\n  esac\n  shift\ndone\nprintf "HTTP/2 200\\r\\ncontent-type: application/json\\r\\n\\r\\n" > "$headers"\nprintf "{\\"ok\\":true,\\"source\\":\\"fake-curl\\"}" > "$body"\n') or {
		panic(err)
	}
	os.chmod(curl_path, 0o755) or { panic(err) }
	old_proxy := os.getenv('https_proxy')
	os.setenv('https_proxy', 'http://127.0.0.1:9', true)
	defer {
		if old_proxy == '' {
			os.unsetenv('https_proxy')
		} else {
			os.setenv('https_proxy', old_proxy, true)
		}
	}
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{
			read_timeout:        1 * time.second
			write_timeout:       1 * time.second
			max_retries:         0
			curl_proxy_fallback: true
			curl_path:           curl_path
		}
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('fetch("https://example.test/quote").then(r => r.json()).then(v => v.source)') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'fake-curl'
}

fn test_fetch_abort_terminates_curl_process() {
	temp_dir := os.join_path(os.temp_dir(), 'vjsx-abort-curl-${os.getpid()}')
	os.mkdir_all(temp_dir) or { panic(err) }
	defer {
		os.rmdir_all(temp_dir) or {}
	}
	curl_path := os.join_path(temp_dir, 'curl')
	started_path := os.join_path(temp_dir, 'started')
	terminated_path := os.join_path(temp_dir, 'terminated')
	os.write_file(curl_path,
		'#!/bin/sh\nprintf started > "${started_path}"\ntrap \'printf terminated > "${terminated_path}"; exit 143\' TERM\nwhile :; do :; done\n') or {
		panic(err)
	}
	os.chmod(curl_path, 0o755) or { panic(err) }
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{
			curl_path: curl_path
		}
	})
	defer {
		session.close()
	}
	ctx := session.context()
	started := time.now()
	value := ctx.eval('
		fetch("https://example.test/slow", {
			signal: AbortSignal.timeout(500)
		}).then(
			() => "resolved",
			(error) => error.name
		)
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	assert resolved.to_string() == 'AbortError'
	assert time.since(started) < 1500 * time.millisecond
	assert os.exists(started_path)
	for _ in 0 .. 100 {
		if os.exists(terminated_path) {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	assert os.exists(terminated_path)
}

fn test_fast_fetch_is_not_starved_by_long_timer() {
	temp_dir := os.join_path(os.temp_dir(), 'vjsx-fast-curl-${os.getpid()}')
	os.mkdir_all(temp_dir) or { panic(err) }
	defer {
		os.rmdir_all(temp_dir) or {}
	}
	curl_path := os.join_path(temp_dir, 'curl')
	os.write_file(curl_path,
		'#!/bin/sh\nheaders=""\nbody=""\nwhile [ "$#" -gt 0 ]; do\n  case "$1" in\n    -D) shift; headers="$1" ;;\n    -o) shift; body="$1" ;;\n  esac\n  shift\ndone\nprintf "HTTP/2 200\\r\\ncontent-type: text/plain\\r\\n\\r\\n" > "$headers"\nprintf "ok" > "$body"\n') or {
		panic(err)
	}
	os.chmod(curl_path, 0o755) or { panic(err) }
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fetch_config: vjsx.FetchGlobalsConfig{
			curl_path: curl_path
		}
	})
	defer {
		session.close()
	}
	ctx := session.context()
	value := ctx.eval('
		(async () => {
			const started = Date.now();
			const timer = setTimeout(() => {}, 2000);
			const response = await fetch("https://example.test/fast");
			const text = await response.text();
			clearTimeout(timer);
			return text + ":" + String(Date.now() - started);
		})()
	') or {
		panic(err)
	}
	defer {
		value.free()
	}
	resolved := session.resolve_value(value) or { panic(err) }
	defer {
		resolved.free()
	}
	parts := resolved.to_string().split(':')
	assert parts[0] == 'ok'
	assert parts[1].int() < 1200
}

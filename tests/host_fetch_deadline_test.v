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

fn test_fetch_uses_curl_when_proxy_env_present() {
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
	old_path := os.getenv('PATH')
	old_proxy := os.getenv('https_proxy')
	os.setenv('PATH', '${temp_dir}:${old_path}', true)
	os.setenv('https_proxy', 'http://127.0.0.1:9', true)
	defer {
		os.setenv('PATH', old_path, true)
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

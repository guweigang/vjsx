module vjsx

import os

fn test_fetch_no_proxy_host_suffix_port_and_ipv6_boundaries() {
	assert fetch_no_proxy_matches('localhost,127.0.0.1,.example.com', 'http://127.0.0.1:8111/x')
	assert fetch_no_proxy_matches('.example.com', 'https://api.example.com/x')
	assert !fetch_no_proxy_matches('.example.com', 'https://notexample.com/x')
	assert !fetch_no_proxy_matches('.example.com', 'https://example.com.attacker.invalid/x')
	assert fetch_no_proxy_matches('api.example.com:443', 'https://api.example.com/x')
	assert !fetch_no_proxy_matches('api.example.com:80', 'https://api.example.com/x')
	assert fetch_no_proxy_matches('[::1]:443', 'https://[::1]/x')
	assert fetch_no_proxy_matches('*', 'https://any.invalid/x')
}

fn test_fetch_environment_proxy_requires_explicit_opt_in_and_env_authority() {
	names := ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy',
		'all_proxy', 'no_proxy']
	mut previous := map[string]?string{}
	for name in names {
		previous[name] = os.getenv_opt(name)
		os.unsetenv(name)
	}
	defer {
		for name in names {
			if value := previous[name] { os.setenv(name, value, true) } else { os.unsetenv(name) }
		}
	}
	os.setenv('HTTPS_PROXY', 'http://127.0.0.1:7890', true)
	os.setenv('NO_PROXY', '127.0.0.1,localhost', true)
	assert fetch_proxy_for(FetchGlobalsConfig{}, host_policy_trusted(), 'https://api.example.com')! == ''
	enabled := FetchGlobalsConfig{ proxy_from_env: true }
	assert fetch_proxy_for(enabled, host_policy_trusted(), 'https://api.example.com')! == 'http://127.0.0.1:7890'
	assert fetch_proxy_for(enabled, HostPolicy{ allow_network: true }, 'https://api.example.com')! == ''
	assert fetch_proxy_for(enabled, host_policy_trusted(), 'http://127.0.0.1:1234')! == ''
	fetch_proxy_for(enabled, HostPolicy{ allow_env_read: true, allow_network: true, network_hosts: ['api.example.com'] }, 'https://api.example.com') or {
		assert err.msg() == 'HTTP proxy endpoint is not allowed'
		return
	}
	assert false
}

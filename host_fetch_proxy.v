module vjsx

import net.urllib
import os

fn fetch_no_proxy_matches(raw string, target string) bool {
	uri := urllib.parse(target) or { return false }
	hostname := uri.hostname().to_lower()
	port := if uri.port() != '' {
		uri.port()
	} else if uri.scheme == 'https' {
		'443'
	} else {
		'80'
	}
	for raw_entry in raw.split(',') {
		mut entry := raw_entry.trim_space().to_lower()
		if entry == '*' { return true }
		if entry == '' { continue }
		if entry.starts_with('[') {
			end := entry.index(']') or { continue }
			suffix := entry[end + 1..]
			if suffix != '' && suffix != ':' + port { continue }
			entry = entry[1..end]
		} else if entry.count(':') == 1 {
			parts := entry.split(':')
			if parts[1] != port { continue }
			entry = parts[0]
		}
		entry = entry.trim_left('.')
		if hostname == entry || hostname.ends_with('.' + entry) { return true }
	}
	return false
}

fn fetch_proxy_for(config FetchGlobalsConfig, policy HostPolicy, target string) !string {
	mut proxy := config.proxy_url
	if proxy == '' && config.proxy_from_env && policy.allow_env_read {
		bypass := os.getenv_opt('no_proxy') or { os.getenv('NO_PROXY') }
		if fetch_no_proxy_matches(bypass, target) { return '' }
		secure := target.to_lower().starts_with('https:')
		proxy = if secure {
			os.getenv_opt('https_proxy') or { os.getenv('HTTPS_PROXY') }
		} else {
			os.getenv_opt('http_proxy') or { os.getenv('HTTP_PROXY') }
		}
		if proxy == '' { proxy = os.getenv_opt('all_proxy') or { os.getenv('ALL_PROXY') } }
	}
	if proxy != '' {
		parsed := urllib.parse(proxy) or { return error('invalid HTTP proxy configuration') }
		if parsed.scheme !in ['http', 'https', 'socks5'] || parsed.hostname() == '' {
			return error('invalid HTTP proxy configuration')
		}
		// A restricted embedder must grant the actual proxy endpoint as well.
		host_policy_allows_url(policy, proxy) or { return error('HTTP proxy endpoint is not allowed') }
	}
	return proxy
}

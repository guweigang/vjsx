module main

import compress.gzip
import crypto.sha512
import encoding.base64
import json2
import net.http
import os
import runtimejs
import vjsx

struct PackageSpec {
	name    string
	version string
}

struct WorkspacePackage {
	name    string
	version string
	path    string
}

struct LockPackage {
	version      string
	resolved     string
	integrity    string
	link         bool
	dependencies map[string]string
}

struct Lockfile {
mut:
	name                       string
	version                    string
	root_dependencies          map[string]string
	root_dev_dependencies      map[string]string
	root_optional_dependencies map[string]string
	root_peer_dependencies     map[string]string
	packages                   map[string]LockPackage
}

struct Installer {
	registry     string
	root         string
	install_root string
	dev          bool
mut:
	installed     map[string]bool
	package_names map[string]bool
	workspaces    map[string]WorkspacePackage
	lock          Lockfile
	warnings      []string
}

fn install_packages(opts CliOptions) !string {
	check_runtime('node')!
	root := os.getwd()
	staging_root := package_staging_root(root, 'install')
	os.rmdir_all(staging_root) or {}
	os.mkdir_all(os.join_path(staging_root, 'node_modules'))!
	defer {
		os.rmdir_all(staging_root) or {}
	}
	mut installer := Installer{
		registry:      normalize_registry(opts.install_registry)!
		root:          root
		install_root:  staging_root
		dev:           opts.install_dev
		installed:     map[string]bool{}
		package_names: map[string]bool{}
	}
	installer.workspaces = load_workspaces(installer.root)!
	installer.lock = load_or_init_lockfile(installer.root, installer.dev)!
	mut specs := opts.install_specs.clone()
	if specs.len == 0 {
		specs = package_json_specs(installer.root, installer.dev)!
	}
	if specs.len == 0 {
		return 'nothing to install\n'
	}
	mut explicit_dependencies := map[string]string{}
	mut requested_names := []string{}
	for spec in specs {
		parsed := parse_package_spec(spec)!
		if parsed.name !in requested_names {
			requested_names << parsed.name
		}
		dependency_version := if parsed.version != '' {
			parsed.version
		} else {
			'latest'
		}
		installer.lock.root_dependencies[parsed.name] = dependency_version
		if installer.dev {
			installer.lock.root_dev_dependencies[parsed.name] = dependency_version
		} else if parsed.name in installer.lock.root_dev_dependencies {
			installer.lock.root_dev_dependencies.delete(parsed.name)
		}
		if parsed.name in installer.lock.root_optional_dependencies {
			installer.lock.root_optional_dependencies.delete(parsed.name)
		}
		if parsed.name in installer.lock.root_peer_dependencies {
			installer.lock.root_peer_dependencies.delete(parsed.name)
		}
		if opts.install_specs.len > 0 {
			explicit_dependencies[parsed.name] = dependency_version
		}
		installer.install_spec(parsed)!
	}
	installer.check_staged_package_entries(requested_names)!
	installer.commit_staged_packages()!
	if explicit_dependencies.len > 0 {
		write_package_json_dependencies(installer.root, explicit_dependencies, installer.dev)!
	}
	write_package_lock(installer.root, installer.lock)!
	mut output := 'installed ${specs.len} package request(s)\n'
	for warning in installer.warnings {
		output += 'warning: ${warning}\n'
	}
	return output
}

fn repair_packages(opts CliOptions) !string {
	check_runtime('node')!
	root := os.getwd()
	lock_path := os.join_path(root, 'package-lock.json')
	if !os.exists(lock_path) {
		return error('repair requires package-lock.json')
	}
	staging_root := package_staging_root(root, 'repair')
	os.rmdir_all(staging_root) or {}
	os.mkdir_all(os.join_path(staging_root, 'node_modules'))!
	defer {
		os.rmdir_all(staging_root) or {}
	}
	mut installer := Installer{
		registry:      normalize_registry(opts.install_registry)!
		root:          root
		install_root:  staging_root
		installed:     map[string]bool{}
		package_names: map[string]bool{}
	}
	installer.workspaces = load_workspaces(root)!
	installer.lock = load_or_init_lockfile(root, true)!
	mut requested_names := []string{}
	if opts.install_specs.len == 0 {
		requested_names = sorted_string_map_keys(installer.lock.root_dependencies)
	} else {
		for raw_name in opts.install_specs {
			parsed := parse_package_spec(raw_name)!
			if parsed.name !in requested_names {
				requested_names << parsed.name
			}
		}
	}
	if requested_names.len == 0 {
		return 'nothing to repair\n'
	}
	for name in requested_names {
		lock_pkg := installer.lock.packages[lock_package_key(name)] or {
			return error('package is not present in package-lock.json: ${name}')
		}
		installer.install_spec(PackageSpec{
			name:    name
			version: lock_pkg.version
		})!
	}
	installer.check_staged_package_entries(requested_names)!
	installer.commit_staged_packages()!
	mut output := 'repaired ${installer.package_names.len} package(s)\n'
	for warning in installer.warnings {
		output += 'warning: ${warning}\n'
	}
	return output
}

fn remove_packages(opts CliOptions) !string {
	check_runtime('node')!
	if opts.install_specs.len == 0 {
		return error('missing package name to remove')
	}
	root := os.getwd()
	mut missing := []string{}
	mut package_names := []string{}
	for spec in opts.install_specs {
		parsed := parse_package_spec(spec)!
		if parsed.name in package_names {
			continue
		}
		package_names << parsed.name
	}
	mut lockfile := load_or_init_lockfile(root, true)!
	manifest_result := remove_package_json_dependencies(root, package_names)!
	for name in package_names {
		if name in lockfile.root_dependencies {
			lockfile.root_dependencies.delete(name)
		}
		if name in lockfile.root_dev_dependencies {
			lockfile.root_dev_dependencies.delete(name)
		}
		if name in lockfile.root_optional_dependencies {
			lockfile.root_optional_dependencies.delete(name)
		}
		if name in lockfile.root_peer_dependencies {
			lockfile.root_peer_dependencies.delete(name)
		}
	}
	reachable := reachable_lock_package_keys(lockfile)
	mut orphan_names := map[string]bool{}
	mut lock_keys := lockfile.packages.keys()
	for key in lock_keys {
		if key !in reachable {
			name := lock_package_name(key)
			if name != '' {
				orphan_names[name] = true
			}
			lockfile.packages.delete(key)
		}
	}
	mut removed := manifest_result.clone()
	for name, _ in orphan_names {
		if lockfile_has_package_name(lockfile, name) {
			continue
		}
		if remove_installed_package_path(package_install_path(root, name))! && name !in removed {
			removed << name
		}
	}
	for name in package_names {
		if name in removed {
			continue
		}
		if !lockfile_has_package_name(lockfile, name)
			&& remove_installed_package_path(package_install_path(root, name))! {
			removed << name
		} else {
			missing << name
		}
	}
	write_package_lock(root, lockfile)!
	mut output := 'removed ${removed.len} package(s)\n'
	for name in missing {
		output += 'warning: ${name} was not installed or declared\n'
	}
	return output
}

fn lock_package_name(key string) string {
	marker := 'node_modules/'
	index := key.last_index(marker) or { return '' }
	remaining := key[index + marker.len..]
	if remaining.starts_with('@') {
		parts := remaining.split('/')
		if parts.len >= 2 {
			return '${parts[0]}/${parts[1]}'
		}
	}
	return remaining.split('/')[0]
}

fn lockfile_has_package_name(lockfile Lockfile, name string) bool {
	for key, _ in lockfile.packages {
		if lock_package_name(key) == name {
			return true
		}
	}
	return false
}

fn reachable_lock_package_keys(lockfile Lockfile) map[string]bool {
	mut reachable := map[string]bool{}
	mut pending := lockfile.root_dependencies.keys()
	mut seen_names := map[string]bool{}
	for pending.len > 0 {
		name := pending[0]
		pending.delete(0)
		if seen_names[name] {
			continue
		}
		seen_names[name] = true
		for key, pkg in lockfile.packages {
			if lock_package_name(key) != name {
				continue
			}
			reachable[key] = true
			for dependency_name, _ in pkg.dependencies {
				if !seen_names[dependency_name] {
					pending << dependency_name
				}
			}
		}
	}
	return reachable
}

fn list_packages(opts CliOptions) !string {
	root := os.getwd()
	lockfile := load_or_init_lockfile(root, true)!
	root_name := if lockfile.name != '' { lockfile.name } else { os.base(root) }
	root_version := if lockfile.version != '' { '@${lockfile.version}' } else { '' }
	mut lines := ['${root_name}${root_version} ${root}']
	mut names := []string{}
	if opts.install_specs.len > 0 {
		for spec in opts.install_specs {
			parsed := parse_package_spec(spec)!
			if parsed.name !in names {
				names << parsed.name
			}
		}
	} else {
		names = sorted_string_map_keys(lockfile.root_dependencies)
	}
	if opts.list_omit.len > 0 {
		names = names.filter(!dependency_type_omitted(root_dependency_type(lockfile, it),
			opts.list_omit))
	}
	if opts.list_json {
		return list_packages_json(root, lockfile, names, opts)
	}
	effective_depth := if opts.install_specs.len > 0 { 0 } else { opts.list_depth }
	for index, name in names {
		requested := lockfile.root_dependencies[name] or { '' }
		mut visiting := []string{}
		append_dependency_tree(mut lines, root, lockfile, name, requested, '',
			index == names.len - 1, effective_depth, mut visiting)
	}
	return lines.join('\n') + '\n'
}

fn list_packages_json(root string, lockfile Lockfile, names []string, opts CliOptions) string {
	root_name := if lockfile.name != '' { lockfile.name } else { os.base(root) }
	parent_label := if lockfile.version != '' {
		'${root_name}@${lockfile.version}'
	} else {
		root_name
	}
	mut root_json := map[string]json2.Any{}
	if lockfile.version != '' {
		root_json['version'] = json2.Any(lockfile.version)
	}
	root_json['name'] = json2.Any(root_name)
	mut dependencies := map[string]json2.Any{}
	mut problems := []string{}
	effective_depth := if opts.install_specs.len > 0 { 0 } else { opts.list_depth }
	for name in names {
		requested := lockfile.root_dependencies[name] or { '' }
		mut visiting := []string{}
		dependency_type := root_dependency_type(lockfile, name)
		dependencies[name] = json2.Any(package_json_node(root, lockfile, name, requested,
			effective_depth, parent_label, dependency_type, mut visiting, mut problems))
	}
	if dependencies.len > 0 {
		root_json['dependencies'] = json2.Any(dependencies)
	}
	if problems.len > 0 {
		root_json['problems'] = json2.Any(string_array_to_any(problems))
		mut error_json := map[string]json2.Any{}
		error_json['code'] = json2.Any('ELSPROBLEMS')
		error_json['summary'] = json2.Any(problems.join('\n'))
		error_json['detail'] = json2.Any('')
		root_json['error'] = json2.Any(error_json)
	}
	return json2.encode(root_json, prettify: true) + '\n'
}

fn root_dependency_type(lockfile Lockfile, name string) string {
	if name in lockfile.root_dev_dependencies {
		return 'dev'
	}
	if name in lockfile.root_optional_dependencies {
		return 'optional'
	}
	if name in lockfile.root_peer_dependencies {
		return 'peer'
	}
	return 'prod'
}

fn dependency_type_omitted(dependency_type string, omit []string) bool {
	return dependency_type in omit
}

fn package_json_node(root string, lockfile Lockfile, name string, requested string, depth_remaining int, parent_label string, dependency_type string, mut visiting []string, mut problems []string) map[string]json2.Any {
	lock_key := lock_package_key(name)
	mut version := requested
	mut deps := map[string]string{}
	mut found := false
	if lock_pkg := lockfile.packages[lock_key] {
		found = true
		version = lock_pkg.version
		deps = lock_pkg.dependencies.clone()
	} else {
		installed_version := installed_package_version(root, name)
		if installed_version != '' {
			found = true
			version = installed_version
		}
	}
	mut node := map[string]json2.Any{}
	if !found {
		problem := 'missing: ${name}@${requested}, required by ${parent_label}'
		node['required'] = json2.Any(requested)
		node['missing'] = json2.Any(true)
		node['dependencyType'] = json2.Any(dependency_type)
		node['problems'] = json2.Any(string_array_to_any([problem]))
		problems << problem
		return node
	}
	node['version'] = json2.Any(version)
	node['overridden'] = json2.Any(false)
	node['dependencyType'] = json2.Any(dependency_type)
	visit_key := '${name}@${version}'
	if visit_key in visiting || depth_remaining == 0 || deps.len == 0 {
		return node
	}
	visiting << visit_key
	child_names := sorted_string_map_keys(deps)
	next_depth := if depth_remaining > 0 { depth_remaining - 1 } else { depth_remaining }
	child_parent := '${name}@${version}'
	mut child_deps := map[string]json2.Any{}
	for child_name in child_names {
		child_deps[child_name] = json2.Any(package_json_node(root, lockfile, child_name,
			deps[child_name], next_depth, child_parent, dependency_type, mut visiting, mut problems))
	}
	visiting.delete(visiting.len - 1)
	if child_deps.len > 0 {
		node['dependencies'] = json2.Any(child_deps)
	}
	return node
}

fn string_array_to_any(values []string) []json2.Any {
	mut out := []json2.Any{}
	for value in values {
		out << json2.Any(value)
	}
	return out
}

fn append_dependency_tree(mut lines []string, root string, lockfile Lockfile, name string, requested string, prefix string, is_last bool, depth_remaining int, mut visiting []string) {
	lock_key := lock_package_key(name)
	mut version := requested
	mut suffix := ''
	mut deps := map[string]string{}
	mut found := false
	if lock_pkg := lockfile.packages[lock_key] {
		found = true
		version = lock_pkg.version
		deps = lock_pkg.dependencies.clone()
		if lock_pkg.link && lock_pkg.resolved != '' {
			suffix = ' -> ${lock_pkg.resolved}'
		}
	} else {
		installed_version := installed_package_version(root, name)
		if installed_version != '' {
			found = true
			version = installed_version
		}
	}
	mut label := name
	if version != '' {
		label += '@${version}'
	}
	if !found {
		label = 'UNMET DEPENDENCY ${label}'
	}
	visit_key := '${name}@${version}'
	cyclic := visit_key in visiting
	if cyclic {
		label += ' cycle'
	}
	has_children := found && !cyclic && depth_remaining != 0 && deps.len > 0
	branch := npm_tree_branch(is_last, has_children)
	lines << '${prefix}${branch}${label}${suffix}'
	if !has_children {
		return
	}
	visiting << visit_key
	child_prefix := prefix + if is_last { '  ' } else { '│ ' }
	child_names := sorted_string_map_keys(deps)
	next_depth := if depth_remaining > 0 { depth_remaining - 1 } else { depth_remaining }
	for index, child_name in child_names {
		append_dependency_tree(mut lines, root, lockfile, child_name, deps[child_name],
			child_prefix, index == child_names.len - 1, next_depth, mut visiting)
	}
	visiting.delete(visiting.len - 1)
}

fn npm_tree_branch(is_last bool, has_children bool) string {
	if has_children {
		return if is_last { '└─┬ ' } else { '├─┬ ' }
	}
	return if is_last { '└── ' } else { '├── ' }
}

fn installed_package_version(root string, name string) string {
	path := os.join_path(package_install_path(root, name), 'package.json')
	if !os.exists(path) {
		return ''
	}
	pkg := json2.decode[json2.Any](os.read_file(path) or { return '' }) or { return '' }
	return any_string_field_optional(pkg.as_map(), 'version')
}

fn sorted_string_map_keys(values map[string]string) []string {
	mut keys := values.keys()
	keys.sort()
	return keys
}

fn normalize_registry(registry string) !string {
	mut trimmed := registry.trim_space()
	if trimmed == '' {
		trimmed = 'https://registry.npmjs.org'
	}
	for trimmed.ends_with('/') {
		trimmed = trimmed[..trimmed.len - 1]
	}
	validate_https_url(trimmed, 'registry')!
	return trimmed
}

fn validate_https_url(url string, kind string) ! {
	if !url.starts_with('https://') {
		return error('${kind} URL must use https://: ${url}')
	}
}

fn validate_package_name(name string) ! {
	if name == '' {
		return error('package name is required')
	}
	if name.len > 214 {
		return error('package name is too long: ${name}')
	}
	if name.contains('\\') || name.starts_with('/') || name.contains('..') {
		return error('invalid package name: ${name}')
	}
	if name.starts_with('@') {
		parts := name.split('/')
		if parts.len != 2 || parts[0].len <= 1 || parts[1] == '' || parts[1].contains('/') {
			return error('invalid scoped package name: ${name}')
		}
		return
	}
	if name.contains('/') || name.starts_with('.') {
		return error('invalid package name: ${name}')
	}
}

fn package_json_specs(root string, include_dev bool) ![]string {
	path := os.join_path(root, 'package.json')
	if !os.exists(path) {
		return error('missing package.json and no package spec was provided')
	}
	manifest := json2.decode[json2.Any](os.read_file(path)!)!
	mut specs := []string{}
	append_dependency_specs(manifest, 'dependencies', mut specs)
	if include_dev {
		append_dependency_specs(manifest, 'devDependencies', mut specs)
	}
	return specs
}

fn append_dependency_specs(manifest json2.Any, field string, mut specs []string) {
	root := manifest.as_map()
	deps_any := root[field] or { return }
	if deps_any !is map[string]json2.Any {
		return
	}
	for name, version_any in deps_any as map[string]json2.Any {
		if version_any is string {
			specs << '${name}@${version_any}'
		}
	}
}

fn parse_package_spec(input string) !PackageSpec {
	spec := input.trim_space()
	if spec == '' {
		return error('empty package spec')
	}
	if spec.starts_with('@') {
		slash := spec.index('/') or { return error('invalid scoped package spec: ${spec}') }
		rest := spec[slash + 1..]
		if at := rest.last_index('@') {
			name := spec[..slash + 1 + at]
			validate_package_name(name)!
			return PackageSpec{
				name:    name
				version: rest[at + 1..]
			}
		}
		validate_package_name(spec)!
		return PackageSpec{
			name: spec
		}
	}
	if at := spec.last_index('@') {
		if at > 0 {
			name := spec[..at]
			validate_package_name(name)!
			return PackageSpec{
				name:    name
				version: spec[at + 1..]
			}
		}
	}
	validate_package_name(spec)!
	return PackageSpec{
		name: spec
	}
}

fn registry_package_path(name string) string {
	return name.replace('/', '%2f')
}

fn (mut installer Installer) install_spec(spec PackageSpec) ! {
	validate_package_name(spec.name)!
	if workspace := installer.workspaces[spec.name] {
		installer.install_workspace(spec, workspace)!
		return
	}
	if spec.version.starts_with('workspace:') {
		return error('workspace dependency not found: ${spec.name}@${spec.version}')
	}
	if lock_pkg := installer.lock_package_for(spec) {
		installer.install_locked_package(spec, lock_pkg)!
		return
	}
	metadata := installer.fetch_metadata(spec.name)!
	version := resolve_package_version(metadata, spec.version)!
	key := '${spec.name}@${version}'
	installer.package_names[spec.name] = true
	if installer.installed[key] {
		return
	}
	installer.installed[key] = true
	versions := any_object(metadata, 'versions')!
	version_info := versions[version] or { return error('version metadata not found: ${key}') }
	dist := any_object(version_info, 'dist')!
	tarball := any_string_field(dist, 'tarball')!
	integrity := any_string_field_optional(dist, 'integrity')
	target := installer.package_install_path(spec.name)
	if !os.exists(target) {
		archive := installer.fetch_tarball(tarball)!
		if integrity != '' {
			verify_integrity(archive, integrity)!
		}
		extract_npm_tarball(archive, target)!
	}
	deps := any_object_optional(version_info, 'dependencies')
	installer.lock_package(spec.name, LockPackage{
		version:      version
		resolved:     tarball
		integrity:    integrity
		dependencies: any_string_map(deps)
	})
	installer.warn_peer_dependencies(spec.name, version_info)
	for dep_name, dep_range_any in deps {
		if dep_range_any is string {
			installer.install_spec(PackageSpec{
				name:    dep_name
				version: dep_range_any
			})!
		}
	}
}

fn (mut installer Installer) install_workspace(spec PackageSpec, workspace WorkspacePackage) ! {
	validate_package_name(spec.name)!
	installer.package_names[spec.name] = true
	if spec.version.starts_with('workspace:')
		&& !workspace_version_satisfies(workspace.version, spec.version) {
		return error('workspace version mismatch: ${spec.name}@${workspace.version} does not satisfy ${spec.version}')
	}
	manifest :=
		json2.decode[json2.Any](os.read_file(os.join_path(workspace.path, 'package.json'))!)!
	deps := any_object_optional(manifest, 'dependencies')
	target := installer.package_install_path(spec.name)
	if !os.exists(target) {
		os.mkdir_all(os.dir(target))!
		os.symlink(workspace.path, target)!
	}
	installer.lock_package(spec.name, LockPackage{
		version:      workspace.version
		resolved:     workspace.path
		link:         true
		dependencies: any_string_map(deps)
	})
	installer.warn_peer_dependencies(spec.name, manifest)
	for dep_name, dep_range_any in deps {
		if dep_range_any is string {
			installer.install_spec(PackageSpec{
				name:    dep_name
				version: dep_range_any
			})!
		}
	}
}

fn (mut installer Installer) install_locked_package(spec PackageSpec, lock_pkg LockPackage) ! {
	validate_package_name(spec.name)!
	key := '${spec.name}@${lock_pkg.version}'
	installer.package_names[spec.name] = true
	if installer.installed[key] {
		return
	}
	installer.installed[key] = true
	target := installer.package_install_path(spec.name)
	if lock_pkg.link {
		if !os.exists(target) {
			os.mkdir_all(os.dir(target))!
			os.symlink(lock_pkg.resolved, target)!
		}
		for dep_name, dep_range in lock_pkg.dependencies {
			installer.install_spec(PackageSpec{
				name:    dep_name
				version: dep_range
			})!
		}
		return
	}
	if !os.exists(target) {
		archive := installer.fetch_tarball(lock_pkg.resolved)!
		if lock_pkg.integrity != '' {
			verify_integrity(archive, lock_pkg.integrity)!
		}
		extract_npm_tarball(archive, target)!
	}
	for dep_name, dep_range in lock_pkg.dependencies {
		installer.install_spec(PackageSpec{
			name:    dep_name
			version: dep_range
		})!
	}
}

fn (installer Installer) lock_package_for(spec PackageSpec) ?LockPackage {
	key := lock_package_key(spec.name)
	lock_pkg := installer.lock.packages[key] or { return none }
	if lock_pkg.link {
		return lock_pkg
	}
	if spec.version == '' || semver_satisfies(lock_pkg.version, spec.version)
		|| lock_pkg.version == spec.version {
		return lock_pkg
	}
	return none
}

fn (mut installer Installer) lock_package(name string, pkg LockPackage) {
	installer.lock.packages[lock_package_key(name)] = pkg
}

fn (installer Installer) package_install_path(name string) string {
	return package_install_path(installer.install_root, name)
}

fn (mut installer Installer) warn_peer_dependencies(name string, version_info json2.Any) {
	peers := any_object_optional(version_info, 'peerDependencies')
	for peer_name, peer_range_any in peers {
		if peer_range_any is string {
			installed := installer.installed_peer_version(peer_name)
			if installed == '' {
				installer.warnings << '${name} requires peer ${peer_name}@${peer_range_any}'
			} else if !semver_satisfies(installed, peer_range_any) && installed != peer_range_any {
				installer.warnings << '${name} requires peer ${peer_name}@${peer_range_any}, installed ${installed}'
			}
		}
	}
}

fn (installer Installer) installed_peer_version(name string) string {
	if workspace := installer.workspaces[name] {
		return workspace.version
	}
	if lock_pkg := installer.lock.packages[lock_package_key(name)] {
		return lock_pkg.version
	}
	return ''
}

fn (installer Installer) fetch_metadata(name string) !json2.Any {
	validate_package_name(name)!
	url := '${installer.registry}/${registry_package_path(name)}'
	resp := http.fetch(url: url, method: .get)!
	if resp.status_code < 200 || resp.status_code >= 300 {
		return error('registry request failed for ${name}: HTTP ${resp.status_code}')
	}
	return json2.decode[json2.Any](resp.body)!
}

fn (installer Installer) fetch_tarball(url string) ![]u8 {
	validate_https_url(url, 'tarball')!
	resp := http.fetch(url: url, method: .get)!
	if resp.status_code < 200 || resp.status_code >= 300 {
		return error('tarball request failed: HTTP ${resp.status_code}: ${url}')
	}
	return resp.body.bytes()
}

fn resolve_package_version(metadata json2.Any, requested string) !string {
	versions := any_object(metadata, 'versions')!
	if versions.len == 0 {
		return error('package has no versions')
	}
	req := requested.trim_space()
	if req == '' || req == '*' || req == 'latest' {
		tags := any_object_optional(metadata, 'dist-tags')
		latest := any_string_field_optional(tags, 'latest')
		if latest != '' {
			return latest
		}
	}
	if req in versions {
		return req
	}
	candidate := best_matching_version(versions, req)
	if candidate != '' {
		return candidate
	}
	return error('no compatible version found for ${any_string_field_optional(metadata.as_map(),
		'name')}@${req}')
}

fn best_matching_version(versions map[string]json2.Any, requested string) string {
	req := requested.trim_space()
	mut best := ''
	for version, _ in versions {
		if req == '' || req == '*' || req == 'latest' || semver_satisfies(version, req) {
			if best == '' || semver_compare(version, best) > 0 {
				best = version
			}
		}
	}
	return best
}

fn semver_satisfies(version string, requested string) bool {
	req := requested.trim_space()
	if req == '' || req == '*' || req == 'latest' {
		return true
	}
	if req.starts_with('^') {
		base := parse_semver(req[1..])
		cur := parse_semver(version)
		return cur.valid && base.valid && cur.major == base.major
			&& semver_compare(version, req[1..]) >= 0
	}
	if req.starts_with('~') {
		base := parse_semver(req[1..])
		cur := parse_semver(version)
		return cur.valid && base.valid && cur.major == base.major && cur.minor == base.minor
			&& semver_compare(version, req[1..]) >= 0
	}
	if req.starts_with('>=') {
		return semver_compare(version, req[2..]) >= 0
	}
	return false
}

struct Semver {
	valid bool
	major int
	minor int
	patch int
}

fn parse_semver(input string) Semver {
	clean := input.trim_space().trim_left('v').split('-')[0].split('+')[0]
	parts := clean.split('.')
	if parts.len < 1 {
		return Semver{}
	}
	return Semver{
		valid: true
		major: parts[0].int()
		minor: if parts.len > 1 { parts[1].int() } else { 0 }
		patch: if parts.len > 2 { parts[2].int() } else { 0 }
	}
}

fn semver_compare(a string, b string) int {
	av := parse_semver(a)
	bv := parse_semver(b)
	if av.major != bv.major {
		return av.major - bv.major
	}
	if av.minor != bv.minor {
		return av.minor - bv.minor
	}
	return av.patch - bv.patch
}

fn package_install_path(root string, name string) string {
	if name.starts_with('@') {
		parts := name.split('/')
		return os.join_path(root, 'node_modules', parts[0], parts[1])
	}
	return os.join_path(root, 'node_modules', name)
}

fn package_staging_root(root string, operation string) string {
	return os.join_path(root, 'node_modules', '.vjsx-${operation}-${os.getpid()}')
}

fn package_check_temp_root(staging_root string, name string) string {
	clean_name := name.replace('@', '').replace('/', '_').replace('\\', '_')
	return os.join_path(staging_root, '.vjsx-check', clean_name)
}

fn package_lifecycle_scripts(package_root string) []string {
	manifest_path := os.join_path(package_root, 'package.json')
	if !os.exists(manifest_path) {
		return []string{}
	}
	manifest := json2.decode[json2.Any](os.read_file(manifest_path) or { return []string{} }) or {
		return []string{}
	}
	scripts := any_object_optional(manifest, 'scripts')
	mut found := []string{}
	for name in ['preinstall', 'install', 'postinstall', 'prepare'] {
		if name in scripts {
			found << name
		}
	}
	return found
}

fn (mut installer Installer) check_staged_package_entries(requested_names []string) ! {
	mut session := vjsx.new_runtime_session()
	defer {
		session.close()
	}
	ctx := session.context()
	install_runtime(ctx, 'node', installer.install_root, os.dir(installer.install_root),
		installer.root, ['vjsx', 'install'])
	for name in requested_names {
		package_root := installer.package_install_path(name)
		if !os.exists(package_root) {
			return error('staged package is missing: ${name}')
		}
		entry := runtimejs.check_runtime_package_entry(ctx, package_root,
			package_check_temp_root(installer.install_root, name)) or {
			return error('package ${name} is not compatible with the vjsx node host: ${err.msg()}')
		}
		if entry == '' {
			installer.warnings << '${name} has no importable default entry; compatibility was not verified'
		}
		scripts := package_lifecycle_scripts(package_root)
		if scripts.len > 0 {
			installer.warnings << '${name} declares lifecycle scripts (${scripts.join(', ')}); vjsx does not run them'
		}
	}
}

fn (installer Installer) commit_staged_packages() ! {
	mut names := installer.package_names.keys()
	names.sort()
	for name in names {
		source := installer.package_install_path(name)
		if !os.exists(source) && !os.is_link(source) {
			return error('staged package is missing: ${name}')
		}
		target := package_install_path(installer.root, name)
		os.mkdir_all(os.dir(target))!
		remove_installed_package_path(target)!
		os.mv(source, target)!
	}
}

fn lock_package_key(name string) string {
	return 'node_modules/${name}'
}

fn workspace_version_satisfies(version string, requested string) bool {
	req := requested.trim_space()
	if req == '' || req == 'workspace:*' {
		return true
	}
	if req.starts_with('workspace:') {
		range := req['workspace:'.len..]
		if range == '*' {
			return true
		}
		return semver_satisfies(version, range) || version == range
	}
	return semver_satisfies(version, req) || version == req
}

fn load_workspaces(root string) !map[string]WorkspacePackage {
	manifest_path := os.join_path(root, 'package.json')
	if !os.exists(manifest_path) {
		return map[string]WorkspacePackage{}
	}
	manifest := json2.decode[json2.Any](os.read_file(manifest_path)!)!
	patterns := workspace_patterns(manifest)
	mut workspaces := map[string]WorkspacePackage{}
	for pattern in patterns {
		for path in workspace_paths(root, pattern)! {
			package_json_path := os.join_path(path, 'package.json')
			if !os.exists(package_json_path) {
				continue
			}
			pkg := json2.decode[json2.Any](os.read_file(package_json_path)!)!
			pkg_map := pkg.as_map()
			name := any_string_field_optional(pkg_map, 'name')
			if name == '' {
				continue
			}
			workspaces[name] = WorkspacePackage{
				name:    name
				version: any_string_field_optional(pkg_map, 'version')
				path:    os.real_path(path)
			}
		}
	}
	return workspaces
}

fn workspace_patterns(manifest json2.Any) []string {
	root := manifest.as_map()
	workspaces_any := root['workspaces'] or { return []string{} }
	if workspaces_any is []json2.Any {
		mut patterns := []string{}
		for item in workspaces_any {
			if item is string {
				patterns << item
			}
		}
		return patterns
	}
	if workspaces_any is map[string]json2.Any {
		packages_any := workspaces_any['packages'] or { return []string{} }
		if packages_any is []json2.Any {
			mut patterns := []string{}
			for item in packages_any {
				if item is string {
					patterns << item
				}
			}
			return patterns
		}
	}
	return []string{}
}

fn workspace_paths(root string, pattern string) ![]string {
	normalized := pattern.trim_space().replace('\\', '/')
	if normalized == '' || normalized.starts_with('/') || normalized.contains('..') {
		return []string{}
	}
	if normalized.contains('*') {
		matches := os.glob(os.join_path(root, normalized)) or { return []string{} }
		mut dirs := []string{}
		for item in matches {
			if os.is_dir(item) {
				dirs << os.real_path(item)
			}
		}
		return dirs
	}
	path := os.join_path(root, normalized)
	if os.is_dir(path) {
		return [os.real_path(path)]
	}
	return []string{}
}

fn load_or_init_lockfile(root string, include_dev bool) !Lockfile {
	manifest_path := os.join_path(root, 'package.json')
	mut name := ''
	mut version := ''
	mut root_dependencies := map[string]string{}
	mut root_dev_dependencies := map[string]string{}
	mut root_optional_dependencies := map[string]string{}
	mut root_peer_dependencies := map[string]string{}
	if os.exists(manifest_path) {
		manifest := json2.decode[json2.Any](os.read_file(manifest_path)!)!
		manifest_map := manifest.as_map()
		name = any_string_field_optional(manifest_map, 'name')
		version = any_string_field_optional(manifest_map, 'version')
		append_dependency_map(manifest, 'dependencies', mut root_dependencies)
		append_dependency_map(manifest, 'optionalDependencies', mut root_optional_dependencies)
		append_dependency_map(manifest, 'peerDependencies', mut root_peer_dependencies)
		merge_dependency_map(mut root_dependencies, root_optional_dependencies)
		merge_dependency_map(mut root_dependencies, root_peer_dependencies)
		if include_dev {
			append_dependency_map(manifest, 'devDependencies', mut root_dev_dependencies)
			merge_dependency_map(mut root_dependencies, root_dev_dependencies)
		}
	}
	lock_path := os.join_path(root, 'package-lock.json')
	mut lockfile := Lockfile{
		name:                       name
		version:                    version
		root_dependencies:          root_dependencies
		root_dev_dependencies:      root_dev_dependencies
		root_optional_dependencies: root_optional_dependencies
		root_peer_dependencies:     root_peer_dependencies
		packages:                   map[string]LockPackage{}
	}
	if !os.exists(lock_path) {
		return lockfile
	}
	lock_json := json2.decode[json2.Any](os.read_file(lock_path)!)!
	lock_map := lock_json.as_map()
	if name == '' {
		name = any_string_field_optional(lock_map, 'name')
	}
	if version == '' {
		version = any_string_field_optional(lock_map, 'version')
	}
	lockfile.name = name
	lockfile.version = version
	packages_any := lock_map['packages'] or { return lockfile }
	if packages_any !is map[string]json2.Any {
		return lockfile
	}
	for path, pkg_any in packages_any as map[string]json2.Any {
		pkg_map := pkg_any.as_map()
		if path == '' {
			lock_dependencies := any_string_map(any_object_optional(pkg_any, 'dependencies'))
			lock_dev_dependencies := any_string_map(any_object_optional(pkg_any, 'devDependencies'))
			lock_optional_dependencies := any_string_map(any_object_optional(pkg_any,
				'optionalDependencies'))
			lock_peer_dependencies := any_string_map(any_object_optional(pkg_any,
				'peerDependencies'))
			if lockfile.root_dependencies.len == 0 {
				lockfile.root_dependencies = lock_dependencies.clone()
			}
			if lockfile.root_optional_dependencies.len == 0 {
				lockfile.root_optional_dependencies = lock_optional_dependencies.clone()
			}
			if lockfile.root_peer_dependencies.len == 0 {
				lockfile.root_peer_dependencies = lock_peer_dependencies.clone()
			}
			merge_dependency_map(mut lockfile.root_dependencies,
				lockfile.root_optional_dependencies)
			merge_dependency_map(mut lockfile.root_dependencies, lockfile.root_peer_dependencies)
			if include_dev {
				if lockfile.root_dev_dependencies.len == 0 {
					lockfile.root_dev_dependencies = lock_dev_dependencies.clone()
				}
				merge_dependency_map(mut lockfile.root_dependencies, lockfile.root_dev_dependencies)
			}
			continue
		}
		lockfile.packages[path] = LockPackage{
			version:      any_string_field_optional(pkg_map, 'version')
			resolved:     any_string_field_optional(pkg_map, 'resolved')
			integrity:    any_string_field_optional(pkg_map, 'integrity')
			link:         any_bool_field_optional(pkg_map, 'link')
			dependencies: any_string_map(any_object_optional(pkg_any, 'dependencies'))
		}
	}
	return lockfile
}

fn append_dependency_map(manifest json2.Any, field string, mut deps map[string]string) {
	root := manifest.as_map()
	deps_any := root[field] or { return }
	if deps_any !is map[string]json2.Any {
		return
	}
	for name, version_any in deps_any as map[string]json2.Any {
		if version_any is string {
			deps[name] = version_any
		}
	}
}

fn merge_dependency_map(mut target map[string]string, source map[string]string) {
	for name, version in source {
		target[name] = version
	}
}

fn write_package_json_dependencies(root string, additions map[string]string, dev bool) ! {
	path := os.join_path(root, 'package.json')
	mut manifest := map[string]json2.Any{}
	if os.exists(path) {
		manifest = json2.decode[json2.Any](os.read_file(path)!)!.as_map()
	}
	field := if dev { 'devDependencies' } else { 'dependencies' }
	mut deps := any_string_map_from_manifest(manifest, field)
	for name, version in additions {
		deps[name] = version
	}
	manifest[field] = json2.Any(string_map_to_any(deps))
	os.write_file(path,
		json2.encode(ordered_package_json_manifest(manifest), prettify: true) + '\n')!
}

fn remove_package_json_dependencies(root string, names []string) ![]string {
	path := os.join_path(root, 'package.json')
	if !os.exists(path) {
		return []string{}
	}
	mut manifest := json2.decode[json2.Any](os.read_file(path)!)!.as_map()
	mut removed := []string{}
	for field in ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'] {
		mut deps := any_string_map_from_manifest(manifest, field)
		mut changed := false
		for name in names {
			if name in deps {
				deps.delete(name)
				if name !in removed {
					removed << name
				}
				changed = true
			}
		}
		if changed {
			if deps.len == 0 {
				manifest.delete(field)
			} else {
				manifest[field] = json2.Any(string_map_to_any(deps))
			}
		}
	}
	if removed.len > 0 {
		os.write_file(path, json2.encode(ordered_package_json_manifest(manifest), prettify: true) +
			'\n')!
	}
	return removed
}

fn remove_installed_package_path(path string) !bool {
	if !os.exists(path) && !os.is_link(path) {
		return false
	}
	if os.is_dir(path) && !os.is_link(path) {
		os.rmdir_all(path)!
		return true
	}
	$if windows {
		if os.is_link(path) && os.is_dir(path) {
			os.rmdir(path)!
			return true
		}
	}
	os.rm(path)!
	return true
}

fn any_string_map_from_manifest(manifest map[string]json2.Any, field string) map[string]string {
	item := manifest[field] or { return map[string]string{} }
	if item is map[string]json2.Any {
		return any_string_map(item)
	}
	return map[string]string{}
}

fn string_map_to_any(values map[string]string) map[string]json2.Any {
	mut out := map[string]json2.Any{}
	for key, value in values {
		out[key] = json2.Any(value)
	}
	return out
}

fn ordered_package_json_manifest(manifest map[string]json2.Any) map[string]json2.Any {
	preferred := [
		'name',
		'version',
		'private',
		'type',
		'description',
		'main',
		'module',
		'exports',
		'bin',
		'scripts',
		'workspaces',
		'dependencies',
		'devDependencies',
		'peerDependencies',
		'optionalDependencies',
		'engines',
		'license',
	]
	mut keys := []string{}
	for key in preferred {
		if key in manifest {
			keys << key
		}
	}
	mut extra := []string{}
	for key, _ in manifest {
		if key !in preferred {
			extra << key
		}
	}
	extra.sort()
	keys << extra
	mut ordered := map[string]json2.Any{}
	for key in keys {
		ordered[key] = manifest[key] or { json2.Any(json2.null) }
	}
	return ordered
}

fn write_package_lock(root string, lockfile Lockfile) ! {
	os.write_file(os.join_path(root, 'package-lock.json'), json2.encode(package_lock_to_json(lockfile),
		prettify: true
	) + '\n')!
}

fn package_lock_to_json(lockfile Lockfile) map[string]json2.Any {
	mut root := map[string]json2.Any{}
	root['name'] = json2.Any(lockfile.name)
	root['version'] = json2.Any(lockfile.version)
	root['lockfileVersion'] = json2.Any(3)
	root['requires'] = json2.Any(true)
	mut packages := map[string]json2.Any{}
	mut root_pkg := map[string]json2.Any{}
	if lockfile.name != '' {
		root_pkg['name'] = json2.Any(lockfile.name)
	}
	if lockfile.version != '' {
		root_pkg['version'] = json2.Any(lockfile.version)
	}
	prod_dependencies := prod_dependency_map(lockfile)
	if prod_dependencies.len > 0 {
		root_pkg['dependencies'] = json2.Any(string_map_to_any(prod_dependencies))
	}
	if lockfile.root_dev_dependencies.len > 0 {
		root_pkg['devDependencies'] = json2.Any(string_map_to_any(lockfile.root_dev_dependencies))
	}
	if lockfile.root_optional_dependencies.len > 0 {
		root_pkg['optionalDependencies'] = json2.Any(string_map_to_any(lockfile.root_optional_dependencies))
	}
	if lockfile.root_peer_dependencies.len > 0 {
		root_pkg['peerDependencies'] = json2.Any(string_map_to_any(lockfile.root_peer_dependencies))
	}
	packages[''] = json2.Any(root_pkg)
	mut keys := lockfile.packages.keys()
	keys.sort()
	for key in keys {
		pkg := lockfile.packages[key]
		mut pkg_json := map[string]json2.Any{}
		if pkg.version != '' {
			pkg_json['version'] = json2.Any(pkg.version)
		}
		if pkg.resolved != '' {
			pkg_json['resolved'] = json2.Any(pkg.resolved)
		}
		if pkg.integrity != '' {
			pkg_json['integrity'] = json2.Any(pkg.integrity)
		}
		if pkg.link {
			pkg_json['link'] = json2.Any(true)
		}
		if pkg.dependencies.len > 0 {
			pkg_json['dependencies'] = json2.Any(string_map_to_any(pkg.dependencies))
		}
		packages[key] = json2.Any(pkg_json)
	}
	root['packages'] = json2.Any(packages)
	return root
}

fn prod_dependency_map(lockfile Lockfile) map[string]string {
	mut deps := map[string]string{}
	for name, version in lockfile.root_dependencies {
		if name !in lockfile.root_dev_dependencies && name !in lockfile.root_optional_dependencies
			&& name !in lockfile.root_peer_dependencies {
			deps[name] = version
		}
	}
	return deps
}

fn verify_integrity(data []u8, integrity string) ! {
	if !integrity.starts_with('sha512-') {
		return
	}
	expected := integrity['sha512-'.len..]
	actual := base64.encode(sha512.sum512(data))
	if actual != expected {
		return error('tarball integrity check failed')
	}
}

fn extract_npm_tarball(archive []u8, target string) ! {
	raw := gzip.decompress(archive)!
	os.mkdir_all(target)!
	mut offset := 0
	for offset + 512 <= raw.len {
		header := raw[offset..offset + 512]
		offset += 512
		if tar_header_is_empty(header) {
			break
		}
		size := tar_octal(header[124..136])
		typeflag := header[156]
		mut name := tar_string(header[0..100])
		prefix := tar_string(header[345..500])
		if prefix != '' {
			name = '${prefix}/${name}'
		}
		payload_end := offset + size
		if payload_end > raw.len {
			return error('invalid tar archive: entry exceeds archive size')
		}
		rel := npm_tar_rel_path(name)
		if rel != '' {
			out_path := os.join_path(target, rel)
			if typeflag == `5` {
				os.mkdir_all(out_path)!
			} else if typeflag == `0` || typeflag == 0 {
				os.mkdir_all(os.dir(out_path))!
				os.write_file_array(out_path, raw[offset..payload_end])!
			}
		}
		offset = payload_end + tar_padding(size)
	}
}

fn tar_header_is_empty(header []u8) bool {
	for b in header {
		if b != 0 {
			return false
		}
	}
	return true
}

fn tar_string(bytes []u8) string {
	mut end := 0
	for end < bytes.len && bytes[end] != 0 {
		end++
	}
	return bytes[..end].bytestr()
}

fn tar_octal(bytes []u8) int {
	mut value := 0
	for b in bytes {
		if b >= `0` && b <= `7` {
			value = value * 8 + int(b - `0`)
		}
	}
	return value
}

fn tar_padding(size int) int {
	remainder := size % 512
	if remainder == 0 {
		return 0
	}
	return 512 - remainder
}

fn npm_tar_rel_path(name string) string {
	mut rel := name.replace('\\', '/')
	if rel.starts_with('package/') {
		rel = rel['package/'.len..]
	}
	if rel == '' || rel.starts_with('/') || rel.contains('../') || rel == '..'
		|| rel.starts_with('../') {
		return ''
	}
	return rel
}

fn any_object(value json2.Any, field string) !map[string]json2.Any {
	root := value.as_map()
	item := root[field] or { return error('missing ${field}') }
	if item is map[string]json2.Any {
		return item
	}
	return error('${field} is not an object')
}

fn any_object_optional(value json2.Any, field string) map[string]json2.Any {
	root := value.as_map()
	item := root[field] or { return map[string]json2.Any{} }
	if item is map[string]json2.Any {
		return item
	}
	return map[string]json2.Any{}
}

fn any_string_field(value map[string]json2.Any, field string) !string {
	item := value[field] or { return error('missing ${field}') }
	if item is string {
		return item
	}
	return error('${field} is not a string')
}

fn any_string_field_optional(value map[string]json2.Any, field string) string {
	item := value[field] or { return '' }
	if item is string {
		return item
	}
	return ''
}

fn any_bool_field_optional(value map[string]json2.Any, field string) bool {
	item := value[field] or { return false }
	if item is bool {
		return item
	}
	return false
}

fn any_string_map(value map[string]json2.Any) map[string]string {
	mut out := map[string]string{}
	for key, item in value {
		if item is string {
			out[key] = item
		}
	}
	return out
}

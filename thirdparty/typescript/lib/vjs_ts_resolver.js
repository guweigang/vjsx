globalThis.__vjs_resolve_ts_module = function(specifier, importerFileName, configText) {
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
		getNewLine: () => "\n"
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

globalThis.__vjs_apply_browser_map = function(pkg, entry) {
	if (!entry || !pkg || typeof pkg.browser !== "object" || Array.isArray(pkg.browser)) {
		return entry;
	}
	const keys = [entry];
	if (!entry.startsWith("./")) {
		keys.push("./" + entry);
	}
	for (const key of keys) {
		if (typeof pkg.browser[key] === "string") {
			return pkg.browser[key];
		}
	}
	return entry;
};

globalThis.__vjs_package_entry = function(packageText, subpath) {
	if (!packageText) {
		return "";
	}
	const pkg = JSON.parse(packageText);
	const key = subpath ? "./" + subpath : ".";
	let entry = "";
	if (pkg.exports) {
		if (typeof pkg.exports === "string" && key === ".") entry = pkg.exports;
		if (typeof pkg.exports === "object" && !Array.isArray(pkg.exports)) {
			if (!entry && !Object.keys(pkg.exports).some((entry) => entry.startsWith(".")) && key === ".") {
				const direct = globalThis.__vjs_pick_package_target(pkg.exports);
				if (direct) entry = direct;
			}
			if (!entry && key in pkg.exports) {
				const mapped = globalThis.__vjs_pick_package_target(pkg.exports[key]);
				if (mapped) entry = mapped;
			}
		}
	}
	if (!entry && key === "." && typeof pkg.main === "string") entry = pkg.main;
	if (!entry && key === "." && typeof pkg.module === "string") entry = pkg.module;
	return globalThis.__vjs_apply_browser_map(pkg, entry);
};

globalThis.__vjs_package_name = function(packageText) {
	if (!packageText) {
		return "";
	}
	const pkg = JSON.parse(packageText);
	return typeof pkg.name === "string" ? pkg.name : "";
};

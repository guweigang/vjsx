globalThis.__vjs_is_commonjs = function(input) {
	const hasEsmSyntax = /^\s*import\s/m.test(input)
		|| /^\s*export\s/m.test(input)
		|| /\bimport\.meta\b/.test(input);
	if (hasEsmSyntax) {
		return false;
	}
	return /module\.exports\s*=|exports\.[A-Za-z_$]|Object\.defineProperty\(exports,|require\s*\(/.test(input);
};

globalThis.__vjs_list_commonjs_exports = function(input) {
	const values = new Set();
	let match;
	const patterns = [
		new RegExp("exports\\.([A-Za-z_\\x24][A-Za-z0-9_\\x24]*)\\s*=", "g"),
		new RegExp("Object\\.defineProperty\\(exports,\\s*[\\\"\\x27]([A-Za-z_\\x24][A-Za-z0-9_\\x24]*)[\\\"\\x27]", "g")
	];
	for (const pattern of patterns) {
		while ((match = pattern.exec(input)) !== null) {
			if (match[1] !== "__esModule" && match[1] !== "default") {
				values.add(match[1]);
			}
		}
	}
	return Array.from(values).join("\n");
};

globalThis.__vjs_list_commonjs_reexports = function(input) {
	const values = new Set();
	const pattern = new RegExp("__exportStar\\s*\\(\\s*require\\s*\\(\\s*[\\\"\\x27]([^\\\"\\x27]+)[\\\"\\x27]\\s*\\)\\s*,\\s*exports\\s*\\)", "g");
	let match;
	while ((match = pattern.exec(input)) !== null) {
		values.add(match[1]);
	}
	return Array.from(values).join("\n");
};

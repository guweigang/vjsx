globalThis.__vjs_is_commonjs = function(input) {
	const hasEsmSyntax = /^\s*import\s/m.test(input)
		|| /^\s*export\s/m.test(input)
		|| /\bimport\.meta\b/.test(input);
	if (hasEsmSyntax) {
		return false;
	}
	return /module\.exports\s*=|exports\.[A-Za-z_$]|Object\.defineProperty\(exports,|require\s*\(/.test(input);
};


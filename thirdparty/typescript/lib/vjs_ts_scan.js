globalThis.__vjs_list_module_imports = function(input, fileName) {
	const values = new Set((ts.preProcessFile(input, true, true).importedFiles || []).map((entry) => entry.fileName));
	const patterns = [
		new RegExp("\\bfrom\\s*[\\\"\\x27]([^\\\"\\x27]+)[\\\"\\x27]", "g"),
		new RegExp("\\bimport\\s*[\\\"\\x27]([^\\\"\\x27]+)[\\\"\\x27]", "g"),
		new RegExp("\\bimport\\s*\\(\\s*[\\\"\\x27]([^\\\"\\x27]+)[\\\"\\x27]\\s*\\)", "g"),
		new RegExp("\\brequire\\s*\\(\\s*[\\\"\\x27]([^\\\"\\x27]+)[\\\"\\x27]\\s*\\)", "g")
	];
	for (const pattern of patterns) {
		let match;
		while ((match = pattern.exec(input)) !== null) {
			values.add(match[1]);
		}
	}
	return Array.from(values).join("\n");
};

globalThis.__vjs_typescript_needs_emit = function(input, fileName) {
	const kind = /\.tsx?$/i.test(fileName) ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
	const sourceFile = ts.createSourceFile(fileName, input, ts.ScriptTarget.Latest, false, kind);
	return !!(sourceFile.transformFlags & ts.TransformFlags.ContainsTypeScript);
};

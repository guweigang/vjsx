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

globalThis.__vjs_normalize_interactive_javascript = function(input, fileName) {
	const sourceText = String(input || "");
	const scriptName = fileName || "<input>";
	const kind = /\.tsx$/i.test(scriptName)
		? ts.ScriptKind.TSX
		: /\.jsx$/i.test(scriptName)
			? ts.ScriptKind.JSX
			: /\.tsx?$/i.test(scriptName)
				? ts.ScriptKind.TS
				: ts.ScriptKind.JS;
	const parse = (source) => ts.createSourceFile(scriptName, source, ts.ScriptTarget.Latest, true, kind);
	const isValid = (sourceFile) => (sourceFile.parseDiagnostics || []).length === 0;
	const countStatements = (node) => {
		let count = 0;
		if (node.statements && typeof node.statements.length === "number") {
			for (const statement of node.statements) {
				if (statement.kind !== ts.SyntaxKind.EmptyStatement) {
					count += 1;
				}
			}
		}
		ts.forEachChild(node, (child) => {
			count += countStatements(child);
		});
		return count;
	};
	let current = sourceText;
	let sourceFile = parse(current);
	if (!isValid(sourceFile)) {
		return sourceText;
	}
	let statementCount = countStatements(sourceFile);
	let offset = 0;
	const lineEndPattern = /\r?\n/g;
	let match;
	while ((match = lineEndPattern.exec(sourceText)) !== null) {
		const newlineStart = match.index;
		const lineStart = sourceText.lastIndexOf("\n", Math.max(0, newlineStart - 1)) + 1;
		let insertAt = newlineStart;
		while (insertAt > 0 && (sourceText[insertAt - 1] === " " || sourceText[insertAt - 1] === "\t")) {
			insertAt -= 1;
		}
		if (sourceText.slice(lineStart, insertAt).trim() === "") {
			continue;
		}
		if (insertAt === 0 || sourceText[insertAt - 1] === ";" || sourceText[insertAt - 1] === ",") {
			continue;
		}
		const currentInsertAt = insertAt + offset;
		const candidate = current.slice(0, currentInsertAt) + ";" + current.slice(currentInsertAt);
		const candidateFile = parse(candidate);
		if (!isValid(candidateFile)) {
			continue;
		}
		const candidateStatementCount = countStatements(candidateFile);
		if (candidateStatementCount <= statementCount) {
			continue;
		}
		current = candidate;
		sourceFile = candidateFile;
		statementCount = candidateStatementCount;
		offset += 1;
	}
	return current;
};

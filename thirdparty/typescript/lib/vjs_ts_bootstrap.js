globalThis.__vjs_format_diagnostics = function(diagnostics) {
	return (diagnostics || [])
		.filter((entry) => entry.category === ts.DiagnosticCategory.Error)
		.map((entry) => {
			const message = ts.flattenDiagnosticMessageText(entry.messageText, "\n");
			if (!entry.file) {
				return message;
			}
			const point = entry.file.getLineAndCharacterOfPosition(entry.start || 0);
			return entry.file.fileName + ":" + String(point.line + 1) + ":" + String(point.character + 1) + " " + message;
		});
};

globalThis.__vjs_normalize_tsconfig = function(configText, fileName) {
	if (!configText) {
		return JSON.stringify({ compilerOptions: {}, configDir: "" });
	}
	const configDir = fileName.replace(/[\\/][^\\/]+$/, "");
	const host = {
		useCaseSensitiveFileNames: !!__vjs_host.useCaseSensitiveFileNames(),
		fileExists: (path) => !!__vjs_host.fileExists(path),
		readFile: (path) => __vjs_host.readFile(path),
		readDirectory: (path, extensions, exclude, include, depth) => __vjs_host.readDirectory(path),
		onUnRecoverableConfigFileDiagnostic: (diagnostic) => {
			throw new Error(globalThis.__vjs_format_diagnostics([diagnostic]).join("\n"));
		}
	};
	const parsed = ts.parseJsonText(fileName, configText);
	const result = ts.parseJsonSourceFileConfigFileContent(parsed, host, configDir, undefined, fileName);
	const diagnostics = globalThis.__vjs_format_diagnostics(result.errors || []);
	if (diagnostics.length > 0) {
		throw new Error(diagnostics.join("\n"));
	}
	return JSON.stringify({
		compilerOptions: result.options || {},
		configDir
	});
};

globalThis.__vjs_transpile_typescript = function(input, fileName, asModule, configText) {
	const config = configText ? JSON.parse(configText) : { compilerOptions: {} };
	const rawCompilerOptions = config.compilerOptions || {};
	const compilerOptions = {};
	const passthroughKeys = [
		"jsx",
		"jsxFactory",
		"jsxFragmentFactory",
		"jsxImportSource",
		"experimentalDecorators",
		"emitDecoratorMetadata",
		"useDefineForClassFields",
		"importsNotUsedAsValues",
		"preserveValueImports",
		"verbatimModuleSyntax",
		"allowArbitraryExtensions"
	];
	for (const key of passthroughKeys) {
		if (rawCompilerOptions[key] != null) {
			compilerOptions[key] = rawCompilerOptions[key];
		}
	}
	compilerOptions.target = ts.ScriptTarget.ESNext;
	compilerOptions.module = asModule ? ts.ModuleKind.ESNext : ts.ModuleKind.None;
	compilerOptions.declaration = false;
	compilerOptions.declarationMap = false;
	compilerOptions.emitDeclarationOnly = false;
	compilerOptions.sourceMap = false;
	compilerOptions.inlineSourceMap = false;
	compilerOptions.inlineSources = false;
	let result;
	try {
		result = ts.transpileModule(input, {
			fileName,
			reportDiagnostics: true,
			compilerOptions
		});
	} catch (err) {
		throw new Error("TypeScript transpile failed for " + fileName + ": " + String((err && err.message) || err));
	}
	const diagnostics = globalThis.__vjs_format_diagnostics(result.diagnostics || []);
	if (diagnostics.length > 0) {
		throw new Error(diagnostics.join("\n"));
	}
	return result.outputText;
};

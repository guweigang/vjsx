const __vjs_commonjs_export_name_pattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

function __vjs_is_valid_commonjs_export_name(name) {
	return __vjs_commonjs_export_name_pattern.test(name) && name !== "__esModule" && name !== "default";
}

function __vjs_commonjs_property_name(node) {
	if (!node) {
		return null;
	}
	if (ts.isIdentifier(node) || ts.isPrivateIdentifier(node)) {
		return node.text;
	}
	if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
		return node.text;
	}
	return null;
}

function __vjs_is_exports_object(node) {
	return !!node
		&& ((ts.isIdentifier(node) && node.text === "exports")
			|| (ts.isPropertyAccessExpression(node)
				&& ts.isIdentifier(node.expression)
				&& node.expression.text === "module"
				&& node.name.text === "exports"));
}

function __vjs_is_exports_member(node) {
	return !!node
		&& ts.isPropertyAccessExpression(node)
		&& __vjs_is_exports_object(node.expression)
		&& __vjs_is_valid_commonjs_export_name(node.name.text);
}

function __vjs_unwrap_commonjs_export_target(node) {
	if (!node) {
		return null;
	}
	if (ts.isParenthesizedExpression(node)) {
		return __vjs_unwrap_commonjs_export_target(node.expression);
	}
	if (ts.isIdentifier(node)) {
		return node.text;
	}
	if (ts.isCallExpression(node)
		&& ts.isIdentifier(node.expression)
		&& node.expression.text === "__toCommonJS"
		&& node.arguments.length > 0) {
		return __vjs_unwrap_commonjs_export_target(node.arguments[0]);
	}
	return null;
}

function __vjs_add_commonjs_object_exports(node, values) {
	if (!node || !ts.isObjectLiteralExpression(node)) {
		return;
	}
	for (const property of node.properties) {
		const name = __vjs_commonjs_property_name(property.name);
		if (name && __vjs_is_valid_commonjs_export_name(name)) {
			values.add(name);
		}
	}
}

function __vjs_collect_commonjs_export_targets(sourceFile) {
	const targets = new Set(["exports"]);
	const visit = (node) => {
		if (ts.isBinaryExpression(node)
			&& node.operatorToken.kind === ts.SyntaxKind.EqualsToken
			&& __vjs_is_exports_object(node.left)) {
			const target = __vjs_unwrap_commonjs_export_target(node.right);
			if (target) {
				targets.add(target);
			}
		}
		ts.forEachChild(node, visit);
	};
	visit(sourceFile);
	return targets;
}

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
	const sourceFile = ts.createSourceFile("vjsx_commonjs_scan.js", input, ts.ScriptTarget.Latest, false, ts.ScriptKind.JS);
	const exportTargets = __vjs_collect_commonjs_export_targets(sourceFile);
	const visit = (node) => {
		if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.EqualsToken) {
			if (__vjs_is_exports_member(node.left)) {
				values.add(node.left.name.text);
			} else if (__vjs_is_exports_object(node.left)) {
				__vjs_add_commonjs_object_exports(node.right, values);
			}
		} else if (ts.isCallExpression(node)) {
			if (ts.isPropertyAccessExpression(node.expression)
				&& __vjs_is_exports_object(node.expression.expression)
				&& node.expression.name.text === "defineProperty"
				&& node.arguments.length >= 2
				&& __vjs_is_exports_object(node.arguments[0])) {
				const name = __vjs_commonjs_property_name(node.arguments[1]);
				if (name && __vjs_is_valid_commonjs_export_name(name)) {
					values.add(name);
				}
			} else if (ts.isIdentifier(node.expression)
				&& node.expression.text === "__export"
				&& node.arguments.length >= 2) {
				const target = __vjs_unwrap_commonjs_export_target(node.arguments[0]);
				if (target && exportTargets.has(target)) {
					__vjs_add_commonjs_object_exports(node.arguments[1], values);
				}
			}
		}
		ts.forEachChild(node, visit);
	};
	visit(sourceFile);
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

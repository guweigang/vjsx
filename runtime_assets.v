module vjsx

import os

const runtime_asset_env_var = 'VJSX_ASSET_ROOT'
const runtime_asset_dev_root = @VMODROOT

pub fn (ctx &Context) set_asset_root(root string) {
	mut target := unsafe { ctx }
	target.asset_root = root.trim_space()
}

pub fn (ctx &Context) asset_root() string {
	if ctx.asset_root != '' {
		return ctx.asset_root
	}
	return os.getenv(runtime_asset_env_var).trim_space()
}

fn runtime_asset_error(rel_path string, root string) IError {
	if root == '' {
		return error('vjsx runtime asset not found: ${rel_path}; set ${runtime_asset_env_var} or ContextConfig.asset_root')
	}
	return error('vjsx runtime asset not found: ${rel_path}; resolved asset root: ${root}')
}

pub fn (ctx &Context) resolve_runtime_asset_path(rel_path string) !string {
	trimmed := rel_path.trim_space()
	if trimmed == '' {
		return error('vjsx runtime asset path is required')
	}
	mut roots := []string{}
	root := ctx.asset_root()
	if root != '' {
		roots << root
	}
	if runtime_asset_dev_root !in roots {
		roots << runtime_asset_dev_root
	}
	for candidate_root in roots {
		candidate := os.join_path(candidate_root, trimmed)
		if os.exists(candidate) {
			return candidate
		}
	}
	return runtime_asset_error(trimmed, if root != '' { root } else { runtime_asset_dev_root })
}

@[manualfree]
pub fn (ctx &Context) eval_runtime_file(rel_path string, args ...EvalArgs) !Value {
	flag := if args.len == 1 { args[0] as int } else { type_global }
	path := ctx.resolve_runtime_asset_path(rel_path)!
	return ctx.eval_file_custom_meta(path, flag, def_set_meta)
}

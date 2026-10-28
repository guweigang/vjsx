import os
import vjsx

fn stat_memory_loop(mut session vjsx.RuntimeSession, count int) ! {
	value := session.call_global('__stat_memory_loop', count)!
	value.free()
}

fn test_fs_stats_keep_snapshot_methods_without_retaining_native_closures() ! {
	root := os.join_path(os.temp_dir(), 'vjsx-stat-memory-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'fixture')
	os.write_file(path, 'data')!
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{ fs_roots: [root] })
	defer { session.close() }
	ctx := session.context()
	global := ctx.js_global()
	global.set('__stat_memory_file', path)
	global.set('__stat_memory_directory', root)
	global.set('__stat_memory_mtime', os.stat(path)!.mtime)
	global.free()
	setup := ctx.run_module('import fs from "node:fs";
 const file = fs.statSync(__stat_memory_file);
 const directory = fs.statSync(__stat_memory_directory);
 const detached = file.isFile;
 if (!detached() || !file.isFile() || file.isDirectory() || file.isSymbolicLink() || !directory.isDirectory() || directory.isFile()) throw Error("Stats snapshot methods");
 if (file.size !== 4 || file.mtime !== __stat_memory_mtime) throw Error("Stats metadata");
 const asyncFile = await fs.stat(__stat_memory_file);
 if (!asyncFile.isFile()) throw Error("Async Stats methods");
 globalThis.__stat_memory_loop = n => {for(let i=0;i<n;i++){const s=fs.statSync(__stat_memory_file); if(!s.isFile() || s.isDirectory()) throw Error("stat");}};
 ', os.join_path(root, 'stat-memory.mjs'))!
	setup.free()
	stat_memory_loop(mut session, 100)!
	session.runtime().run_gc()
	gc_collect()
	before_native := gc_memory_use()
	before_js := session.memory_usage().memory_used_size
	stat_memory_loop(mut session, 5000)!
	session.runtime().run_gc()
	gc_collect()
	after_native := gc_memory_use()
	after_js := session.memory_usage().memory_used_size
	assert after_js <= before_js + 512 * 1024, 'Stats objects retained JS references: ${before_js} -> ${after_js}'
	if gc_is_enabled() {
		assert after_native <= before_native + 2 * 1024 * 1024, 'Stats methods retained native captures: ${before_native} -> ${after_native}'
	}
}

import os
import vjsx

fn test_runtime_session_close_closes_unclosed_sqlite_connections() {
	base_dir := os.join_path(@VMODROOT, 'tests', '.tmp_runtime_session_sqlite_cleanup')
	os.mkdir_all(base_dir) or { panic(err) }
	db_path := os.join_path(base_dir, 'cleanup.db')
	os.rm(db_path) or {}
	mut session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [base_dir]
	})
	ctx := session.context()
	script :=
		'
		globalThis.__cleanup_db = await import("sqlite").then((mod) => mod.open({ path: "' +
		db_path.replace('\\', '\\\\') +
		'" }));
		await globalThis.__cleanup_db.exec("create table if not exists items (id integer primary key, name text)");
		await globalThis.__cleanup_db.begin();
		await globalThis.__cleanup_db.exec("insert into items(name) values (?)", ["alpha"]);
	'
	ctx.eval(script, vjsx.type_module) or { panic(err) }
	ctx.end()
	assert os.exists(db_path)
	session.close()
	mut verify_session := vjsx.new_node_runtime_session(vjsx.ContextConfig{}, vjsx.NodeRuntimeConfig{
		fs_roots: [base_dir]
	})
	defer {
		verify_session.close()
	}
	verify_ctx := verify_session.context()
	verify_script := '
		const db = await import("sqlite").then((mod) => mod.open({ path: "' +
		db_path.replace('\\', '\\\\') +
		'" }));
		const total = await db.scalar("select count(*) from items");
		await db.exec("insert into items(name) values (?)", ["beta"]);
		await db.close();
		globalThis.__cleanup_total = total;
	'
	verify_ctx.eval(verify_script, vjsx.type_module) or { panic(err) }
	verify_ctx.end()
	count := verify_ctx.js_global('__cleanup_total')
	assert count.to_string() == '0'
	count.free()
	os.rm(db_path) or {}
	os.rmdir(base_dir) or {}
}
